#!/bin/bash

# =================================================================
# Project: Smart Telegram Content-Reader
# Description: Enhanced Asset Proxy for Images and Media
# Author: izHaman
# =================================================================

# --- 1. Round-robin Persistence Logic ---
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

echo "[🔄] Smart Sync Started | Channel: $SLUG ($(($INDEX + 1))/$TOTAL)"

# --- 2. Workspace Setup ---
mkdir -p feeds/images

# --- 3. Content Acquisition ---
BASE_URL="https://rsshub.rssforever.com/telegram/channel"
TMP_FILE="feeds/$SLUG.xml.tmp"

HTTP_CODE=$(curl -L -s -o "$TMP_FILE" -w "%{http_code}" \
  "$BASE_URL/$SLUG" --max-time 60 --connect-timeout 15 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" != "200" ]] || [[ ! -s "$TMP_FILE" ]]; then
  echo "  [!] Error: Fetch failed for $SLUG (HTTP $HTTP_CODE)."
  rm -f "$TMP_FILE"
else
  # --- 4. Deep Asset Mirroring (Images & Media) ---
  echo "  [📸] Mirroring media assets to GitHub domain..."
  
  # Finding all possible Telegram media formats (telesco.pe links)
  # Improved regex to catch more media types
  grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u | while read -r img_url; do
      # Remove any trailing parameters if they exist
      clean_url=$(echo "$img_url" | cut -d'?' -f1)
      hash_name=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1).jpg
      local_path="feeds/images/$hash_name"
      
      if [[ ! -f "$local_path" ]]; then
          curl -s -L --max-filesize 10M -o "$local_path" "$img_url" --max-time 20
      fi
      
      # Use GitHub's /raw/ path for all identified media
      CDN_URL="https://github.com/izHaman/Telegram-SSR/raw/main/feeds/images/$hash_name"
      sed -i "s|$img_url|$CDN_URL|g" "$TMP_FILE"
  done

  # --- 5. Python Optimization Bridge ---
  python3 optimizer.py || echo "  [!] Python optimization skipped."

  # --- 6. Finalizing Feed Update ---
  mv "$TMP_FILE" "feeds/$SLUG.xml"
  echo "  [+] $SLUG.xml updated with full media proxy."
fi

# --- 7. Maintenance & Cleanup ---
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;
echo "{\"index\": $NEXT_INDEX}" > state.json

# --- 8. Git Deployment ---
git config --global user.name "Smart-Sync-Bot"
git config --global user.email "actions@github.com"

git add feeds/*.xml feeds/images/*.jpg state.json

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "chore: full media sync $SLUG"
  git push
  echo "  [🚀] Changes pushed to GitHub."
else
  echo "  [✔] No new content to push."
fi
