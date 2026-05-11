#!/bin/bash
# =============================================================================
# Fetch-feeds.sh — GitHub Actions entrypoint for the Telegram RSS mirror pipeline
# =============================================================================
#
# PURPOSE
# -------
# Runs on a cron schedule (and optionally on manual dispatch) inside GitHub
# Actions.  Orchestrates three steps:
#
#   1. Bridge  — bridge.py authenticates to Telegram via MTProto and downloads
#                images into feeds/media/, recording their paths in a manifest.
#
#   2. Fetch   — curl pulls raw RSS XML from one of several public RSSHub mirror
#                instances for a rotating chunk of 4 Telegram channels.
#
#   3. Process — process_feed.py rewrites each XML file:
#                  • CDN image URLs → permanent raw.githubusercontent.com URLs
#                  • Video/audio CDN URLs → GitHub-proxied URLs + bilingual banner
#                  • Injects <enclosure> and <media:content> tags for Feeder Android
#
# After the three steps, stale local media files are pruned and the results are
# committed and pushed back to the repository so the RSS feed URLs remain stable.
#
# CHANNEL ROTATION
# ----------------
# Fetching all 12 channels every run would consume ~12 minutes of Actions time
# (network I/O + image downloads) and hit RSSHub rate limits.  Instead, we
# maintain a cursor in state.json and advance it by CHUNK_SIZE=4 each run.
# With 12 channels total, every channel is refreshed every 3 runs (≈ 3 × cron
# interval), which balances freshness against resource usage.
#
# ERROR HANDLING
# --------------
# `set -euo pipefail` ensures any unhandled error aborts the whole script,
# preventing partial/corrupt state from being committed.  Per-channel errors
# (empty curl response, processing failure) are handled explicitly with
# informational warnings so one bad channel does not block the others.
#
# =============================================================================

set -euo pipefail   # -e abort on error  -u treat unset vars as errors  -o pipefail propagate pipe failures

# ---------------------------------------------------------------------------
# GitHub raw URL configuration
# ---------------------------------------------------------------------------
# RAW_BASE_URL is the public HTTP prefix for files committed to main.
# process_feed.py appends relative paths to build permanent media URLs.
# GITHUB_REPOSITORY is automatically set by GitHub Actions (owner/repo format).
RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main"

# Default thumbnail injected for text-only posts so Feeder's card view is never blank.
PLACEHOLDER_URL="${RAW_BASE_URL}/feeds/media/default_img/text_placeholder.jpg"

# ---------------------------------------------------------------------------
# Rotation state
# ---------------------------------------------------------------------------
# state.json persists the cursor between workflow runs.
# Using Python for JSON parsing instead of `grep -oP` for two reasons:
#   1. grep -oP requires GNU extensions unavailable on BSD/macOS (Actions runners
#      can vary; Python is always available).
#   2. Python's json module handles non-standard whitespace safely.
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(python3 -c "import json; print(json.load(open('state.json'))['index'])")

# ── Step 1: Telegram MTProto Image Bridge ────────────────────────────────────
# Pre-fetches images for the channels listed in CHANNELS (bridge.py) via the
# official Telegram API, avoiding ephemeral CDN URLs entirely for those channels.
# bridge.py is a no-op when TELEGRAM_* secrets are not configured, so this step
# is safe to run even in forks or PRs that lack the secrets.
echo "Step 1: Running Telegram Media Bridge..."
python3 bridge.py

# ── Step 2: Fetch RSS feeds from RSSHub ──────────────────────────────────────
# RSSHub is an open-source RSS generator that can convert Telegram channels to
# RSS 2.0 XML.  Multiple public instances are tried in order: if the first
# returns an XML without any video/media URLs (indicating a rate-limit or
# partial response), we fall back to the next instance.
RSSHUB_INSTANCES=(
    "https://rsshub.rssforever.com"   # primary — usually fastest
    "https://rsshub.moeyy.cn"         # secondary fallback
    "https://rsshub.app"              # official instance — rate-limited but reliable
)

# Full list of Telegram channel slugs to mirror.
# CHUNK_SIZE channels are fetched per run; the cursor in state.json determines which.
# To add a channel: append its slug here AND add it to the CHANNELS list in bridge.py
# if you also want MTProto image pre-fetching for it.
CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv"
          "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019"
          "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}   # 12 — used for modulo wrap-around
CHUNK_SIZE=4            # channels fetched per run; adjust to taste (affects freshness vs. speed)

mkdir -p feeds/media/default_img   # ensure directory exists before curl writes to it

# Guard: warn clearly if the placeholder image is missing from the repository.
# Without it, text-only posts will have a broken image URL in their feed card.
# To fix: commit your image to feeds/media/default_img/text_placeholder.jpg
if [[ ! -f "feeds/media/default_img/text_placeholder.jpg" ]]; then
    echo "[warn] feeds/media/default_img/text_placeholder.jpg not found in repo."
    echo "       Text-only posts will show a broken placeholder until you commit this file."
fi

echo "Step 2: Fetching RSSHub chunk (index ${INDEX})..."

for (( i=0; i<CHUNK_SIZE; i++ )); do
    # Modulo arithmetic wraps the cursor around the channel list, so runs 0→2→4
    # cycle through all 12 channels without index-out-of-bounds errors.
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/${SLUG}.xml.tmp"

    # ── Instance fallback loop ────────────────────────────────────────────────
    # Try each RSSHub instance in order.  We use `grep -qiE` to test for the
    # presence of video/media URLs because a "successful" HTTP 200 response from
    # a rate-limited instance may contain a valid but media-stripped XML — we
    # want the richest version we can get.
    # `-E` (extended regex) is used instead of `-P` (Perl regex) for POSIX
    # portability; BSD grep (macOS Actions runners) does not support -P.
    for INSTANCE in "${RSSHUB_INSTANCES[@]}"; do
        curl -L -s -o "$TMP_FILE" \
             -A "Mozilla/5.0" \
             "${INSTANCE}/telegram/channel/${SLUG}?include_video=1" \
             --connect-timeout 15 \
             --max-time 60
        # If the response contains media indicators, this instance is good enough;
        # break out of the fallback loop and proceed with processing.
        grep -qiE "(mp4|video|telesco\.pe)" "$TMP_FILE" && break
    done

    if [[ -s "$TMP_FILE" ]]; then
        # Delegate all XML transformation to process_feed.py.
        # Using a Python script instead of sed/awk/perl avoids:
        #   • GNU-vs-BSD incompatibilities in regex flags
        #   • Shell-injection when URLs contain &, ?, or % characters
        #   • Line-length limits in sed's in-place mode
        # The script reads from stdin (< "$TMP_FILE") and writes to stdout
        # (> "feeds/${SLUG}.xml"), keeping the original .tmp until success.
        python3 process_feed.py "$SLUG" "$RAW_BASE_URL" "$PLACEHOLDER_URL" \
            < "$TMP_FILE" > "feeds/${SLUG}.xml"

        rm -f "$TMP_FILE"
        echo "  Done: feeds/${SLUG}.xml"
    else
        echo "  [warn] Empty response for @${SLUG}, skipping."
        rm -f "$TMP_FILE"
        # Do NOT exit — continue with the next channel in the chunk.
    fi
done

# ── Maintenance: advance cursor ───────────────────────────────────────────────
# Write the next starting index so the following scheduled run picks up
# where this one left off.  Modulo wraps back to 0 after the last channel.
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": ${NEXT_INDEX}}" > state.json

# ── Maintenance: prune stale media files ─────────────────────────────────────
# Files older than 48 hours that are not tracked by git are safe to delete:
#   • git-tracked files are referenced by live feed URLs on raw.githubusercontent.com
#     and must not be removed even if they are old.
#   • Untracked files are ephemeral downloads from the current or previous run
#     that were never committed (e.g. a failed commit, or files replaced by newer
#     downloads).  Removing them prevents the media directory from growing without bound.
#
# `git ls-files --error-unmatch` exits non-zero for untracked files; the `||`
# operator then removes them.  We silence the stderr output of ls-files to keep
# the Actions log clean.
find feeds/media -maxdepth 1 -type f -mmin +2880 | while read -r f; do
    git ls-files --error-unmatch "$f" 2>/dev/null || rm -f "$f"
done

# ── Commit and push ───────────────────────────────────────────────────────────
# Configure the git identity for the commit.  Using the standard github-actions
# bot identity means the commit shows up with the Actions bot avatar in the
# GitHub UI, making it visually distinct from human commits.
git config --global user.name  "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"

# `git add .` stages everything: updated feed XMLs, new media files, manifest.json,
# and the updated state.json cursor.
git add .

# `&& git push` is intentional: if there are no changes (all channels returned
# empty XML or no new media was downloaded), `git commit` exits non-zero and
# the push is skipped, avoiding empty commits in the history.
git commit -m "sync: feeds and media cache update" && git push
