#!/bin/bash

# Extract 'username/repo' dynamically for portability
REPO_FULL_NAME=$GITHUB_REPOSITORY

# Persistence: track which channels to process in this run
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

# Channel list - Add or remove slugs here
CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "persian_rockstar" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

mkdir -p feeds/images

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    # Fetch feed from RSSHub proxy
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
      # Scrape media URLs before they expire or get blocked
      urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
      
      for img_url in $urls; do
          clean_url=$(echo "$img_url" | cut -d'?' -f1)
          hash_name=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1).jpg
          local_path="feeds/images/$hash_name"
          
          # Only download if asset isn't already in the local cache
          if [[ ! -f "$local_path" ]]; then
              curl -s -L --max-filesize 10M -o "$local_path" "$img_url" --max-time 20
          fi
          
          if [[ -f "$local_path" ]]; then
              # BYPASS STRATEGY:
              # 1. Point to the Raw GitHub file
              # 2. Wrap it in Weserv proxy to bypass Iran's SNI filtering and fix MIME headers
              RAW_URL="https://raw.githubusercontent.com/${REPO_FULL_NAME}/main/feeds/images/$hash_name"
              FINAL_PROXY_URL="https://images.weserv.nl/?url=${RAW_URL}&default=${RAW_URL}"
              
              sed -i "s|$img_url|$FINAL_PROXY_URL|g" "$TMP_FILE"
          fi
      done
      mv "$TMP_FILE" "feeds/$SLUG.xml"
    fi
done

# Update state for next cycle
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

# Execute Python-based optimization
python3 optimizer.py
# Clean up older assets to keep repo size under control
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;

# Automated commit using GitHub Actions identity
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: fix media rendering using raw-proxy tunnel" && git push
