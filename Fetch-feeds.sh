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

# ---------------------------------------------------------------------------
# Ensure folders exist
# ---------------------------------------------------------------------------
mkdir -p feeds
mkdir -p feeds/media/default_img

# ---------------------------------------------------------------------------
# Cleanup orphan tmp files
# ---------------------------------------------------------------------------
find feeds -type f -name "*.tmp" -delete || true

# ── Step 1: Telegram MTProto Image Bridge ────────────────────────────────────
echo "Step 1: Running Telegram Media Bridge..."

set +e
python3 bridge.py
BRIDGE_EXIT=$?
set -e

if [[ $BRIDGE_EXIT -ne 0 ]]; then
    echo "[warn] bridge.py exited with code ${BRIDGE_EXIT}"
    echo "[warn] Continuing workflow anyway..."
fi

# ── Step 2: Fetch RSS feeds from RSSHub ──────────────────────────────────────
RSSHUB_INSTANCES=(
    "https://rsshub.rssforever.com"
    "https://rsshub.moeyy.cn"
    "https://rsshub.app"
)

CHANNELS=(
    "mamlekate"
    "ircfspace"
    "vahidonline"
    "iranintltv"
    "drtel"
    "hatricktv"
    "raptv"
    "jadivarlog"
    "digitechirchannel"
    "STCdownload"
    "khateraaat"
    "dw_farsi"
)

TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4

echo "Step 2: Fetching RSSHub chunk (index ${INDEX})..."

# ── Priority channel: always fetch regardless of chunk ─────────────────────
PRIORITY_SLUG="STCdownload"
TMP_FILE="feeds/${PRIORITY_SLUG}.xml.tmp"

set +e

for INSTANCE in "${RSSHUB_INSTANCES[@]}"; do
    echo "  Trying priority feed from: ${INSTANCE}"

    curl -L -s \
         --retry 3 \
         --retry-delay 2 \
         --retry-all-errors \
         --connect-timeout 20 \
         --max-time 90 \
         -A "Mozilla/5.0" \
         -o "$TMP_FILE" \
         "${INSTANCE}/telegram/channel/${PRIORITY_SLUG}?include_video=1"

    if [[ ! -s "$TMP_FILE" ]]; then
        echo "    Empty response."
        continue
    fi

    if grep -qiE "(<rss|<feed|mp4|mp3|video|audio|telesco\.pe)" "$TMP_FILE"; then
        echo "    Valid feed detected."
        break
    fi

    echo "    Invalid response."
done

if [[ -s "$TMP_FILE" ]]; then
    python3 process_feed.py \
        "$PRIORITY_SLUG" \
        "$RAW_BASE_URL" \
        "$PLACEHOLDER_URL" \
        < "$TMP_FILE" \
        > "feeds/${PRIORITY_SLUG}.xml"

    echo "  Done (priority): feeds/${PRIORITY_SLUG}.xml"
fi

rm -f "$TMP_FILE"

set -e

# ── Chunk loop ───────────────────────────────────────────────────────────────
for (( i=0; i<CHUNK_SIZE; i++ )); do

    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"

    # Skip duplicate priority channel
    [[ "$SLUG" == "$PRIORITY_SLUG" ]] && continue

    TMP_FILE="feeds/${SLUG}.xml.tmp"

    echo "  Fetching @${SLUG}..."

    SUCCESS=0

    for INSTANCE in "${RSSHUB_INSTANCES[@]}"; do

        echo "    Trying instance: ${INSTANCE}"

        curl -L -s \
             --retry 3 \
             --retry-delay 2 \
             --retry-all-errors \
             --connect-timeout 20 \
             --max-time 90 \
             -A "Mozilla/5.0" \
             -o "$TMP_FILE" \
             "${INSTANCE}/telegram/channel/${SLUG}?include_video=1"

        # Empty response
        [[ ! -s "$TMP_FILE" ]] && continue

        # Validate actual feed content
        if grep -qiE "(<rss|<feed|mp4|mp3|video|audio|telesco\.pe)" "$TMP_FILE"; then
            SUCCESS=1
            break
        fi
    done

    if [[ $SUCCESS -eq 1 ]]; then

        set +e

        python3 process_feed.py \
            "$SLUG" \
            "$RAW_BASE_URL" \
            "$PLACEHOLDER_URL" \
            < "$TMP_FILE" \
            > "feeds/${SLUG}.xml"

        PROCESS_EXIT=$?

        set -e

        if [[ $PROCESS_EXIT -eq 0 ]]; then
            echo "  Done: feeds/${SLUG}.xml"
        else
            echo "  [warn] process_feed.py failed for @${SLUG}"
            rm -f "feeds/${SLUG}.xml"
        fi

    else
        echo "  [warn] Invalid/empty response for @${SLUG}"
    fi

    rm -f "$TMP_FILE"

done

# ── Advance cursor ────────────────────────────────────────────────────────────
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": ${NEXT_INDEX}}" > state.json

# ── Prune stale media files ───────────────────────────────────────────────────
echo "Step 3: Pruning stale media..."

while IFS= read -r f; do

    git ls-files --error-unmatch "$f" >/dev/null 2>&1 || {
        echo "  Removing stale file: $f"
        rm -f "$f"
    }

done < <(
    find feeds/media \
        -maxdepth 1 \
        -type f \
        -mmin +2880
)

# ── Git config ───────────────────────────────────────────────────────────────
git config --global user.name  "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"

# ── Commit and push ───────────────────────────────────────────────────────────
echo "Step 4: Commit & push..."

git add .

if git diff --cached --quiet; then
    echo "No changes detected."
else

    git commit -m "sync: feeds and media cache update"

    git push \
        "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
        2>&1 || echo "[warn] git push failed"

fi

echo "Workflow completed."
