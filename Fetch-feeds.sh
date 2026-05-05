#!/bin/bash

# =================================================================
# Project: Smart Telegram Content-Reader
# Description: Advanced RSS Proxy & Image Optimizer for Telegram
# Author: izHaman
# =================================================================

# --- 1. Round-robin Persistence Logic ---
# Ensures that only one channel is processed per execution cycle
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
# Create directory for assets if it doesn't exist
mkdir -p feeds/images

# --- 3. Content Acquisition ---
# Fetching RSS content from the bridge
BASE_URL="https://rsshub.rssforever.com/telegram/channel"
TMP_FILE="feeds/$SLUG.xml.tmp"

HTTP_CODE=$(curl -L -s -o "$TMP_FILE" -w "%{http_code}" \
  "$BASE_URL/$SLUG" --max-time 60 --connect-timeout 15 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" != "200" ]] || [[ ! -s "$TMP_FILE" ]]; then
  echo "  [!] Error: Fetch failed for $SLUG (HTTP $HTTP_CODE)."
  rm -f "$TMP_FILE"
else
  # --- 4. Asset Mirroring & Proxying ---
  echo "  [📸] Mirroring assets to GitHub main domain..."
  
  # Extract Telegram image URLs and replace with GitHub proxy links
  grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s]*' "$TMP_FILE" | sort -u | while read -r img_url; do
      hash_name=$(echo -n "$img_url" | md5sum | cut -d' ' -f1).jpg
      local_path="feeds/images/$hash_name"
      
      # Download image only if not already cached
      if [[ ! -f "$local_path" ]]; then
          curl -s -L --max-filesize 5M -o "$local_path" "$img_url" --max-time 15
      fi
      
      # Use GitHub /raw/ path for whitelist compatibility
      CDN_URL="https://github.com/izHaman/Telegram-SSR/raw/main/feeds/images/$hash_name"
      sed -i "s|$img_url|$CDN_URL|g" "$TMP_FILE"
  done

  # --- 5. Python Optimization Bridge ---
  # Run the Python optimizer to compress new images
  python3 optimizer.py || echo "  [!] Python optimization skipped."

  # --- 6. Finalizing Feed Update ---
  # Force-update the feed file to ensure all proxy links are live
  mv "$TMP_FILE" "feeds/$SLUG.xml"
  echo "  [+] $SLUG.xml updated successfully."
fi

# --- 7. Maintenance & Cleanup ---
# Housekeeping: Remove images older than 3 days
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;
echo "{\"index\": $NEXT_INDEX}" > state.json

# --- 8. Git Deployment ---
git config --global user.name "Smart-Sync-Bot"
git config --global user.email "actions@github.com"

# Stage modified files
git add feeds/*.xml feeds/images/*.jpg state.json

# Commit and push only if changes exist
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "chore: smart sync $SLUG and optimize assets"
  git push
  echo "  [🚀] Changes pushed to GitHub."
else
  echo "  [✔] No new changes to push."
fi
