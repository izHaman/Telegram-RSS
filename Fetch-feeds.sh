#!/bin/bash

# =================================================================
# Project: Smart Telegram Content-Reader (STC-Reader)
# Description: Fixed Media Linking & Direct CDN Access
# Repo Name: STC-Reader
# Author: izHaman
# =================================================================

echo "[🚀] Smart Ultra-Safe Sync Started"

# --- 1. Chunking Logic ---
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

echo "[📊] Processing chunk starting at index: $INDEX"

# --- 2. Workspace Setup ---
mkdir -p feeds/images
BASE_URL="https://rsshub.rssforever.com/telegram/channel"

# --- 3. Process the Chunk ---
for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    
    echo "----------------------------------------"
    echo "[🔄] Fetching ($(($i+1))/$CHUNK_SIZE): $SLUG"
    
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    HTTP_CODE=$(curl -L -s -o "$TMP_FILE" -w "%{http_code}" \
      -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/110.0.0.0 Safari/537.36" \
      "$BASE_URL/$SLUG" --max-time 60 --connect-timeout 15 2>/dev/null || echo "000")

    if [[ "$HTTP_CODE" != "200" ]] || [[ ! -s "$TMP_FILE" ]]; then
      echo "  [!] Error: Fetch failed for $SLUG (HTTP $HTTP_CODE)."
      rm -f "$TMP_FILE"
    else
      # --- Asset Mirroring & Proxying ---
      echo "  [📸] Mirroring assets and fixing links..."
      
      # Extract unique Telegram URLs
      urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
      
      for img_url in $urls; do
          clean_url=$(echo "$img_url" | cut -d'?' -f1)
          hash_name=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1).jpg
          local_path="feeds/images/$hash_name"
          
          if [[ ! -f "$local_path" ]]; then
              curl -s -L --max-filesize 10M -o "$local_path" "$img_url" --max-time 20
          fi
          
          # DIRECT LINK: Pointing to raw.githubusercontent.com for STC-Reader
          CDN_URL="https://raw.githubusercontent.com/izHaman/STC-Reader/main/feeds/images/$hash_name"
          
          # 1. Update image src in the description
          sed -i "s|$img_url|$CDN_URL|g" "$TMP_FILE"
          
          # 2. Inject enclosure tag for RSS readers to recognize media content
          sed -i "/<\/item>/i \    <enclosure url=\"$CDN_URL\" length=\"0\" type=\"image/jpeg\" />" "$TMP_FILE"
      done

      mv "$TMP_FILE" "feeds/$SLUG.xml"
      echo "  [+] $SLUG.xml updated with direct STC-Reader links."
    fi
    
    if [[ $i -lt $((CHUNK_SIZE - 1)) ]]; then
        SLEEP_TIME=$(( ( RANDOM % 21 )  + 20 ))
        echo "  [⏳] Anti-Rate-Limit: Sleeping $SLEEP_TIME seconds..."
        sleep $SLEEP_TIME
    fi
done

# --- 4. State Update ---
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

# --- 5. Finalizing ---
python3 optimizer.py || echo "  [!] Image optimization skipped."
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;

# --- 6. Deployment ---
git config --global user.name "Smart-Sync-Bot"
git config --global user.email "actions@github.com"
git add feeds/*.xml feeds/images/*.jpg state.json

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "fix: media links for STC-Reader repo"
  git push
  echo "  [🚀] Successfully deployed to GitHub."
else
  echo "  [✔] No changes detected."
fi
