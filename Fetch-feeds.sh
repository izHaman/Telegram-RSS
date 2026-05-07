#!/bin/bash

# initialize state file if missing
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

# source channels
CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "persian_rockstar" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

mkdir -p feeds/images

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    # fetch raw feed from rsshub
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
      # extract media links
      urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
      
      for img_url in $urls; do
          clean_url=$(echo "$img_url" | cut -d'?' -f1)
          hash_name=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1).jpg
          local_path="feeds/images/$hash_name"
          
          # grab the image if we don't have it locally
          if [[ ! -f "$local_path" ]]; then
              curl -s -L --max-filesize 10M -o "$local_path" "$img_url" --max-time 20
          fi
          
          if [[ -f "$local_path" ]]; then
              # using raw.githubusercontent for direct access
              GITHUB_URL="https://raw.githubusercontent.com/izHaman/STC-Reader/main/feeds/images/$hash_name"
              sed -i "s|$img_url|$GITHUB_URL|g" "$TMP_FILE"
          fi
      done

      # insert enclosure tags properly into each item
      # this logic ensures we only add it once per item to avoid breaking the parser
      sed -i '/<item>/,/<\/item>/ {
          /<img src="\([^"]*\)"/ {
              h; s/.*<img src="\([^"]*\)".*/    <enclosure url="\1" type="image\/jpeg" \/>/; x
          }
          /<\/item>/ {
              x; p; x
          }
      }' "$TMP_FILE"

      mv "$TMP_FILE" "feeds/$SLUG.xml"
    fi
done

# update rotation index
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

# run image processing and clean up old assets
python3 optimizer.py
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;

# commit changes to repo
git config --global user.name "Smart-Sync-Bot"
git config --global user.email "actions@github.com"
git add .
git commit -m "sync: update feeds and assets" && git push
