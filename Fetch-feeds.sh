#!/bin/bash

REPO_FULL_NAME=$GITHUB_REPOSITORY
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "persian_rockstar" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

mkdir -p feeds/images

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    # Bypass simple scraping blocks
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
      # Scrape all image URLs
      urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
      
      for img_url in $urls; do
          clean_url=$(echo "$img_url" | cut -d'?' -f1)
          hash_name=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1).jpg
          local_path="feeds/images/$hash_name"
          
          if [[ ! -f "$local_path" ]]; then
              curl -s -L --max-filesize 10M -o "$local_path" "$img_url" --max-time 20
          fi
          
          if [[ -f "$local_path" ]]; then
              # Statically CDN is the "Secret Sauce" here. 
              # It works in Iran and bypasses the 'nosniff' issue.
              FINAL_URL="https://cdn.statically.io/gh/${REPO_FULL_NAME}/main/feeds/images/$hash_name"
              
              sed -i "s|$img_url|$FINAL_URL|g" "$TMP_FILE"
          fi
      done
      mv "$TMP_FILE" "feeds/$SLUG.xml"
    fi
done

NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

python3 optimizer.py
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;

git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: switch to statically cdn for cross-region reliability" && git push
