#!/bin/bash

CHANNELS=(
  "mamlekate" "ircfspace" "vahidonline" "iranintltv"
  "persian_rockstar" "hatricktv" "iholymaryat70"
  "jadivarlog" "digitechirchannel" "whynationsfail2019"
  "khateraaat" "dw_farsi"
)

BASE_URL="https://rsshub.rssforever.com/telegram/channel"
mkdir -p feeds

TOTAL=${#CHANNELS[@]}
COUNTER=0

for slug in "${CHANNELS[@]}"; do
  COUNTER=$((COUNTER+1))
  echo "[$COUNTER/$TOTAL] Checking: $slug"
  
  # Download feed (no comparison, always overwrite)
  HTTP_CODE=$(curl -L -s -o "feeds/$slug.xml" -w "%{http_code}" \
    "$BASE_URL/$slug" --max-time 60 --connect-timeout 15 2>/dev/null || echo "000")
  
  if [ "$HTTP_CODE" != "200" ]; then
    echo "  ⚠️ HTTP $HTTP_CODE - failed to update"
    # Keep existing file on error, don't delete
  else
    if [ ! -s "feeds/$slug.xml" ] || ! grep -q "<?xml" "feeds/$slug.xml" 2>/dev/null; then
      echo "  ⚠️ Invalid or empty XML - keeping previous feed if exists"
    else
      echo "  ✅ Feed updated successfully"
    fi
  fi
  
  # If not last channel, wait 5 minutes
  if [ $COUNTER -lt $TOTAL ]; then
    echo "  ⏳ Waiting 5 minutes before next channel..."
    sleep 300
  fi
done

echo "✅ Finished checking $TOTAL channels"

# Git operations
git config --global user.name "Content-Monitor"
git config --global user.email "bot@github.com"
git add feeds/*.xml

if [ -n "$(git status --porcelain)" ]; then
  git commit -m "Update feeds: $(date +'%Y-%m-%d %H:%M')"
  git push
  echo "✅ Committed and pushed changes."
else
  echo "📭 No changes to commit (but feeds were checked)."
fi
