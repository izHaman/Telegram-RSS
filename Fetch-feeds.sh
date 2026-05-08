#!/bin/bash

# Extract 'username/repo' dynamically from the GitHub environment
REPO_FULL_NAME=$GITHUB_REPOSITORY

# Persist and rotate channel pointer across action runs to avoid timeouts
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

# Target Telegram channels
CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "persian_rockstar" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 # Process in small batches to stay within runtime limits

mkdir -p feeds/images

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    # Fetch from RSSHub with a generic browser User-Agent
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
      # Scrape media endpoints from the feed content
      urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
      
      for img_url in $urls; do
          clean_url=$(echo "$img_url" | cut -d'?' -f1)
          hash_name=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1).jpg
          local_path="feeds/images/$hash_name"
          
          # Caching: only download if not already present in the repo
          if [[ ! -f "$local_path" ]]; then
              curl -s -L --max-filesize 10M -o "$local_path" "$img_url" --max-time 20
          fi
          
          if [[ -f "$local_path" ]]; then
              # LAYERED PROXY STRATEGY:
              # 1. GitHub as host
              # 2. Fastly jsDelivr as CDN (bypasses GitHub 'nosniff' blocks)
              # 3. Weserv as Image Proxy (strips CORS/Referer headers and enforces image/jpeg MIME)
              CDN_URL="https://fastly.jsdelivr.net/gh/${REPO_FULL_NAME}@main/feeds/images/$hash_name"
              FINAL_PROXY_URL="https://images.weserv.nl/?url=${CDN_URL}&default=${CDN_URL}"
              
              sed -i "s|$img_url|$FINAL_PROXY_URL|g" "$TMP_FILE"
          fi
      done
      mv "$TMP_FILE" "feeds/$SLUG.xml"
    fi
done

# Save offset for the next automated trigger
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

# Image optimization and housekeeping
python3 optimizer.py
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;

# Use standard GitHub Actions bot credentials for commits
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: optimized media delivery with image proxy layering" && git push
