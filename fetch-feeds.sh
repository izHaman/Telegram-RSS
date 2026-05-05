#!/bin/bash

# Read current index from file
if [ ! -f "state.json" ]; then
  echo '{"index": 0}' > state.json
fi

INDEX=$(cat state.json | grep -o '"index": [0-9]*' | grep -o '[0-9]*')

CHANNELS=(
  "mamlekate" "ircfspace" "vahidonline" "iranintltv"
  "persian_rockstar" "hatricktv" "iholymaryat70"
  "jadivarlog" "digitechirchannel" "whynationsfail2019"
  "khateraaat" "dw_farsi"
)

TOTAL=${#CHANNELS[@]}
SLUG="${CHANNELS[$INDEX]}"
NEXT_INDEX=$((INDEX + 1))
if [ $NEXT_INDEX -ge $TOTAL ]; then
  NEXT_INDEX=0
fi

echo "[$((INDEX+1))/$TOTAL] Checking: $SLUG"

BASE_URL="https://rsshub.rssforever.com/telegram/channel"
mkdir -p feeds

HTTP_CODE=$(curl -L -s -o "feeds/$SLUG.xml" -w "%{http_code}" \
  "$BASE_URL/$SLUG" --max-time 60 --connect-timeout 15 2>/dev/null || echo "000")

if [ "$HTTP_CODE" != "200" ]; then
  echo "  ⚠️ HTTP $HTTP_CODE - failed to update"
else
  if [ ! -s "feeds/$SLUG.xml" ] || ! grep -q "<?xml" "feeds/$SLUG.xml" 2>/dev/null; then
    echo "  ⚠️ Invalid XML - keeping previous feed"
  else
    echo "  ✅ Updated successfully"
  fi
fi

# Save next index
echo "{\"index\": $NEXT_INDEX}" > state.json

# Git operations
git config --global user.name "Content-Monitor"
git config --global user.email "bot@github.com"
git add feeds/*.xml state.json

if [ -n "$(git status --porcelain)" ]; then
  git commit -m "Update $SLUG at $(date +'%H:%M')"
  git push
  echo "✅ Committed and pushed."
else
  echo "📭 No changes to commit."
fi
