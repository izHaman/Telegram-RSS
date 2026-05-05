#!/bin/bash

# --- 1. Persistence Logic ---
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

CHANNELS=(
  "mamlekate" "ircfspace" "vahidonline" "iranintltv"
  "persian_rockstar" "hatricktv" "iholymaryat70"
  "jadivarlog" "digitechirchannel" "whynationsfail2019"
  "khateraaat" "dw_farsi"
)

TOTAL=${#CHANNELS[@]}
SLUG="${CHANNELS[$INDEX]}"
NEXT_INDEX=$(( (INDEX + 1) % TOTAL ))

echo "[$(($INDEX + 1))/$TOTAL] Processing: $SLUG"

# --- 2. Workspace Setup ---
mkdir -p feeds/images

# --- 3. Content Acquisition ---
BASE_URL="https://rsshub.rssforever.com/telegram/channel"
TMP_FILE="feeds/$SLUG.xml.tmp"

HTTP_CODE=$(curl -L -s -o "$TMP_FILE" -w "%{http_code}" \
  "$BASE_URL/$SLUG" --max-time 60 --connect-timeout 15 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" != "200" ]] || [[ ! -s "$TMP_FILE" ]]; then
  echo "  ! Fetch failed (HTTP $HTTP_CODE)."
  rm -f "$TMP_FILE"
else
  # --- 4. Asset Mirroring & Proxying ---
  echo "  > Mirroring assets to GitHub main domain..."
  grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s]*' "$TMP_FILE" | sort -u | while read -r img_url; do
      hash_name=$(echo -n "$img_url" | md5sum | cut -d' ' -f1).jpg
      local_path="feeds/images/$hash_name"
      
      if [[ ! -f "$local_path" ]]; then
          curl -s -L --max-filesize 5M -o "$local_path" "$img_url" --max-time 15
      fi
      
      # Using GitHub Main Domain as a Proxy (Whitelist Friendly)
      CDN_URL="https://github.com/izHaman/Telegram-SSR/blob/main/feeds/images/$hash_name?raw=true"
      sed -i "s|$img_url|$CDN_URL|g" "$TMP_FILE"
  done

  # --- 5. Python Optimization Bridge ---
  python3 optimizer.py || echo "  ! Skipping optimization"

  # --- 6. Change Detection ---
  if [[ -f "feeds/$SLUG.xml" ]]; then
    if diff -I '<lastBuildDate>' -I '<pubDate>' -I '<updated>' "feeds/$SLUG.xml" "$TMP_FILE" > /dev/null; then
      echo "  = No new content."
      rm "$TMP_FILE"
    else
      mv "$TMP_FILE" "feeds/$SLUG.xml"
      echo "  + Feed updated."
    fi
  else
    mv "$TMP_FILE" "feeds/$SLUG.xml"
  fi
fi

# --- 7. Maintenance & Cleanup ---
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;
echo "{\"index\": $NEXT_INDEX}" > state.json

# --- 8. Deployment ---
git config --global user.name "gh-actions-bot"
git config --global user.email "actions@github.com"
git add feeds/*.xml feeds/images/*.jpg state.json

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "chore: smart sync $SLUG and optimize assets"
  git push
  echo "  # Changes deployed."
else
  echo "  # Clean workspace."
fi
