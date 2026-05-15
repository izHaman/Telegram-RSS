#!/bin/bash
# =============================================================================
# Fetch-feeds.sh — GitHub Actions entrypoint for the Telegram RSS mirror pipeline
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# GitHub raw URL configuration
# ---------------------------------------------------------------------------
RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main"
PLACEHOLDER_URL="${RAW_BASE_URL}/feeds/media/default_img/text_placeholder.jpg"

# ---------------------------------------------------------------------------
# Rotation state
# ---------------------------------------------------------------------------
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(python3 -c "import json; print(json.load(open('state.json'))['index'])")

# ── Step 1: Telegram MTProto Image Bridge ────────────────────────────────────
echo "Step 1: Running Telegram Media Bridge..."
python3 bridge.py

# ── Step 2: Fetch RSS feeds from RSSHub ──────────────────────────────────────
RSSHUB_INSTANCES=(
    "https://rsshub.rssforever.com"
    "https://rsshub.moeyy.cn"
    "https://rsshub.app"
)

CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv"
          "raptv" "jadivarlog" "digitechirchannel" "STCdownload"
          "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4

mkdir -p feeds/media/default_img

echo "Step 2: Fetching RSSHub chunk (index ${INDEX})..."

# ── Priority channel: always fetch regardless of chunk ─────────────────────
PRIORITY_SLUG="STCdownload"
TMP_FILE="feeds/${PRIORITY_SLUG}.xml.tmp"

set +e
for INSTANCE in "${RSSHUB_INSTANCES[@]}"; do
    curl -L -s -o "$TMP_FILE" \
         -A "Mozilla/5.0" \
         "${INSTANCE}/telegram/channel/${PRIORITY_SLUG}?include_video=1" \
         --connect-timeout 15 \
         --max-time 60
    grep -qiE "(mp4|mp3|video|audio|telesco\.pe)" "$TMP_FILE" && break
done

if [[ -s "$TMP_FILE" ]]; then
    python3 process_feed.py "$PRIORITY_SLUG" "$RAW_BASE_URL" "$PLACEHOLDER_URL" \
        < "$TMP_FILE" > "feeds/${PRIORITY_SLUG}.xml"
    rm -f "$TMP_FILE"
    echo "  Done (priority): feeds/${PRIORITY_SLUG}.xml"
fi
set -e

# ── Chunk loop ───────────────────────────────────────────────────────────────
for (( i=0; i<CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/${SLUG}.xml.tmp"

    for INSTANCE in "${RSSHUB_INSTANCES[@]}"; do
        curl -L -s -o "$TMP_FILE" \
             -A "Mozilla/5.0" \
             "${INSTANCE}/telegram/channel/${SLUG}?include_video=1" \
             --connect-timeout 15 \
             --max-time 60
        grep -qiE "(mp4|mp3|video|audio|telesco\.pe)" "$TMP_FILE" && break || true
    done

    if [[ -s "$TMP_FILE" ]]; then
        python3 process_feed.py "$SLUG" "$RAW_BASE_URL" "$PLACEHOLDER_URL" \
            < "$TMP_FILE" > "feeds/${SLUG}.xml" || true
        rm -f "$TMP_FILE"
        echo "  Done: feeds/${SLUG}.xml"
    else
        echo "  [warn] Empty response for @${SLUG}, skipping."
        rm -f "$TMP_FILE"
    fi
done

# ── Advance cursor ────────────────────────────────────────────────────────────
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": ${NEXT_INDEX}}" > state.json

# ── Prune stale media files ───────────────────────────────────────────────────
while IFS= read -r f; do
    git ls-files --error-unmatch "$f" 2>/dev/null || rm -f "$f"
done < <(find feeds/media -maxdepth 1 -type f -mmin +2880)

# ── Commit and push ───────────────────────────────────────────────────────────
git config --global user.name  "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"

git add .
git diff --cached --quiet || (git commit -m "sync: feeds and media cache update" && git push "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" 2>&1)
echo "Git push exit code: $?"
