#!/bin/bash
set -euo pipefail

# GitHub Raw base URL for serving committed media files
RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main"
PLACEHOLDER_URL="${RAW_BASE_URL}/feeds/media/default_img/text_placeholder.jpg"

# Read rotation index with Python — grep -oP is a GNU extension unavailable
# on BSD/macOS and fragile against non-standard whitespace in the JSON.
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(python3 -c "import json; print(json.load(open('state.json'))['index'])")

# ── Step 1: Bridge ────────────────────────────────────────────────────────────
# Pre-fetch images via MTProto and populate feeds/media/manifest.json.
# process_feed.py consults the manifest to avoid redundant CDN downloads.
echo "Step 1: Running Telegram Media Bridge..."
python3 bridge.py

# ── Step 2: Fetch + process RSSHub feeds ─────────────────────────────────────
RSSHUB_INSTANCES=(
    "https://rsshub.rssforever.com"
    "https://rsshub.moeyy.cn"
    "https://rsshub.app"
)

CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv"
          "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019"
          "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4

mkdir -p feeds/media/default_img

echo "Step 2: Fetching RSSHub chunk (index ${INDEX})..."
for (( i=0; i<CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/${SLUG}.xml.tmp"

    # Try each instance in order; stop as soon as one returns recognisable media
    for INSTANCE in "${RSSHUB_INSTANCES[@]}"; do
        curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" \
            "${INSTANCE}/telegram/channel/${SLUG}?include_video=1" \
            --connect-timeout 15 --max-time 60
        # -E (extended regex) is portable; -P (Perl regex) is GNU-only
        grep -qiE "(mp4|video|telesco\.pe)" "$TMP_FILE" && break
    done

    if [[ -s "$TMP_FILE" ]]; then
        # Delegate all XML processing to the Python feed processor:
        #   - localises images (manifest → cache → CDN download → GitHub raw URL)
        #   - preserves video/audio CDN URLs so Feeder can stream them directly
        #   - injects <enclosure> + <media:content> for Feeder Android
        #   - injects placeholder thumbnail for text-only posts
        # Python str.replace() is used internally, so URLs with special chars
        # (&, ?, %) no longer break the substitution (fixes the sed -i bug).
        python3 process_feed.py "$SLUG" "$RAW_BASE_URL" "$PLACEHOLDER_URL" \
            < "$TMP_FILE" > "feeds/${SLUG}.xml"

        rm -f "$TMP_FILE"
        echo "  Done: feeds/${SLUG}.xml"
    else
        echo "  [warn] Empty response for @${SLUG}, skipping."
        rm -f "$TMP_FILE"
    fi
done

# ── Maintenance ───────────────────────────────────────────────────────────────

# Advance the rotation cursor for the next scheduled run
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": ${NEXT_INDEX}}" > state.json

# Remove local media files older than 48 h that are NOT tracked by git.
# Checking git-tracking prevents us from deleting committed files that are
# still referenced by live feed URLs on raw.githubusercontent.com.
find feeds/media -maxdepth 1 -type f -mmin +2880 | while read -r f; do
    git ls-files --error-unmatch "$f" 2>/dev/null || rm -f "$f"
done

# ── Commit & Push ─────────────────────────────────────────────────────────────
git config --global user.name  "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: feeds and media cache update" && git push
