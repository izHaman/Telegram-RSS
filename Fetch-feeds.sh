#!/bin/bash

# =================================================================
# Project: Smart Telegram Content-Reader (STC-Reader)
# Description: Fixed Media Linking & Direct CDN Access
# Repo Name: STC-Reader
# Author: izHaman
# =================================================================

echo "[🚀] Smart Sync Started"

# --- 1. State & Logic ---
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

CHANNELS=(
  "mamlekate" "ircfspace" "vahidonline" "iranintltv"
  "persian_rockstar" "hatricktv" "iholymaryat70"
  "jadivarlog" "digitechirchannel" "whynationsfail2019"
  "khateraaat" "dw_farsi"
)

TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

# --- 2. Setup ---
mkdir -p feeds/images
BASE_URL="https://rsshub.rssforever.com/telegram/channel"

# --- 3. Processing ---
for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    
    echo "----------------------------------------"
    echo "[🔄] Fetching: $SLUG"
    
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    # Fetch with Browser User-Agent
    HTTP_CODE=$(curl -L -s -o "$TMP_FILE" -w "%{http_code}" \
      -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/110.0.0.0 Safari/537.36" \
      "$BASE_URL/$SLUG" --max-time 60 --connect-timeout 15 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" != "200" ]] || [[ ! -s "$TMP_FILE" ]]; then
      echo "  [!] Skip: Fetch failed (HTTP $HTTP_CODE)"
      rm -f "$TMP_FILE"
    else
      # --- Asset Replacement Logic ---
      echo "  [📸] Processing media for $SLUG..."
      
      # Extract ALL telegram media links from the file
      urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
      
      for img_url in $urls; do
          # Clean URL for filename (remove params)
          clean_url=$(echo "$img_url" | cut -d'?' -f1)
          hash_name=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1).jpg
          local_path="feeds/images/$hash_name"
          
          # Download if needed
          if [[ ! -f "$local_path" ]]; then
              curl -s -L --max-filesize 15M -o "$local_path" "$img_url" --max-time 20
          fi
          
          # Direct Link Replacement (The most stable way)
          if [[ -f "$local_path" ]]; then
              CDN_URL="https://raw.githubusercontent.com/izHaman/STC-Reader/main/feeds/images/$hash_name"
              # Replace globally without breaking XML tags
              sed -i "s|$img_url|$CDN_URL|g" "$TMP_FILE"
          fi
      done

      # Move tmp to final XML
      mv "$TMP_FILE" "feeds/$SLUG.xml"
      echo "  [+] $SLUG.xml is now valid and updated."
    fi
    
    [[ $i -lt $((CHUNK_SIZE - 1)) ]] && sleep $(( ( RANDOM % 15 )  + 10 ))
done

# --- 4. Finalize ---
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

python3 optimizer.py || echo "  [!] Optimizer skipped."
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;

# --- 5. Deploy ---
git config --global user.name "Smart-Sync-Bot"
git config --global user.email "actions@github.com"
git add feeds/*.xml feeds/images/*.jpg state.json

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "fix: restore xml integrity and update feeds"
  git push
else
  echo "  [✔] No changes."
fi
