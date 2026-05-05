#!/bin/bash

# =================================================================
# Project: Smart Telegram Content-Reader
# Description: Advanced RSS Proxy & Image Optimizer for Telegram
# Author: Gemini AI Collaboration
# =================================================================

# --- 1. Round-robin Persistence Logic ---
# Ensures that only one channel is processed per execution to manage resources
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
# Create necessary directory structure if it doesn't exist
mkdir -p feeds/images

# --- 3. Content Acquisition ---
# Fetching RSS content from the bridge with defined timeouts
BASE_URL="https://rsshub.rssforever.com/telegram/channel"
TMP_FILE="feeds/$SLUG.xml.tmp"

HTTP_CODE=$(curl -L -s -o "$TMP_FILE" -w "%{http_code}" \
  "$BASE_URL/$SLUG" --max-time 60 --connect-timeout 15 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" != "200" ]] || [[ ! -s "$TMP_FILE" ]]; then
  echo "  [!] Error: Could not fetch $SLUG (HTTP $HTTP_CODE). Moving to next cycle."
  rm -f "$TMP_FILE"
else
  # --- 4. Asset Mirroring & Proxying ---
  echo "  [📸] Mirroring assets to GitHub main domain..."
  
  # Extract Telegram image URLs and replace them with GitHub proxy links
  grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s]*' "$TMP_FILE" | sort -u | while read -r img_url; do
      # Generate a unique filename using MD5 hash of the original URL
      hash_name=$(echo -n "$img_url" | md5sum | cut -d' ' -f1).jpg
      local_path="feeds/images/$hash_name"
      
      # Download the image only if it doesn't already exist locally
      if [[ ! -f "$local_path" ]]; then
          curl -s -L --max-filesize 5M -o "$local_path" "$img_url" --max-time 15
      fi
      
      # Using GitHub's /raw/ path on the main domain for better compatibility in whitelist environments
      CDN_URL="https://github.com/izHaman/Telegram-SSR/raw/main/feeds/images/$hash_name"
      sed -i "s|$img_url|$CDN_URL|g" "$TMP_FILE"
  done

  # --- 5. Python Optimization Bridge ---
  # Calling the Python script to compress images for mobile performance
  python3 optimizer.py || echo "  [!] Python optimization skipped due to execution error."

  # --- 6. Deployment Finalization ---
  # Force-updating the XML file to ensure proxy links are always applied
  mv "$TMP_
