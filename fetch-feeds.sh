#!/bin/bash

# --- 1. State Persistence ---
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

echo "[$(($INDEX + 1))/$TOTAL] Fetching: $SLUG"

# --- 2. Environment Setup ---
mkdir -p feeds/images

# --- 3. Content Fetching ---
BASE_URL="https://rsshub.rssforever.com/telegram/channel"
TMP_FILE="feeds/$SLUG.xml.tmp"

HTTP_CODE=$(curl -L -s -o "$TMP_FILE" -w "%{http_code}" \
  "$BASE_URL/$SLUG" --max-time 60 --connect-timeout 15 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" != "200" ]] || [[ ! -s "$TMP_FILE" ]]; then
  echo "  ! Request failed (HTTP $HTTP_CODE). skipping."
  rm -f "$TMP_FILE"
else
  # --- 4. Image Mirroring ---
  echo "  > Syncing media assets..."
  grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s]*' "$TMP_FILE" | sort -u | while read -r img_url; do
      hash_name=$(echo -n "$img_url" | md5sum | cut -d' ' -f1).jpg
      local_path="feeds/images/$hash_name"
      
      if [[ ! -f "$local_path" ]]; then
          curl -s -L --max-filesize 5M -o "$local_path" "$img_url" --max-time 15
      fi
      
      # Rewrite to local GitHub CDN
      CDN_URL="https://raw.githubusercontent.com/izHaman/Telegram-SSR/main/feeds/images/$hash_name"
      sed -i "s|$img_url|$CDN_URL|g" "$TMP_FILE"
  done

  # --- 5. Media Optimization (Python Bridge) ---
  if [[ -d "feeds/images" ]]; then
    python3 optimizer.py
  fi

  # --- 6. Content Integrity Check ---
  if [[ -f "feeds/$SLUG.xml" ]]; then
    if diff -I '<lastBuildDate>' -I '<pubDate>' -I '<updated>' "feeds/$SLUG.xml" "$TMP_FILE" > /dev/null; then
      echo "  = Content identical. No update."
      rm "$TMP_FILE"
    else
      mv "$TMP_FILE" "feeds/$SLUG.xml"
      echo "  + Updated: feeds/$SLUG.xml"
    fi
  else
    mv "$TMP_FILE" "feeds/$SLUG.xml"
  fi
fi

# --- 7. Maintenance & Cleanup ---
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;
echo "{\"index\": $NEXT_INDEX}" > state.json

# --- 8. VCS Deployment ---
git config --global user.name "gh-actions-bot"
git config --global user.email "actions@github.com"
git add feeds/*.xml feeds/images/*.jpg state.json

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "chore: sync $SLUG and optimize assets"
  git push
  echo "  # Commit pushed."
else
  echo "  # No changes to commit."
fi

