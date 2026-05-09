#!/bin/bash

# Get repo name from environment
REPO_FULL_NAME=$GITHUB_REPOSITORY

# Handle channel rotation state
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

mkdir -p feeds/images

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    # Fetch feed from RSSHub with a generic user-agent
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
      # Extract telegram media links
      urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
      
      for img_url in $urls; do
          clean_url=$(echo "$img_url" | cut -d'?' -f1)
          hash_name=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1).jpg
          local_path="feeds/images/$hash_name"
          
          # Cache images locally if they don't exist
          if [[ ! -f "$local_path" ]]; then
              curl -s -L --max-filesize 10M -o "$local_path" "$img_url" --max-time 20
          fi
          
          if [[ -f "$local_path" ]]; then
              # Link to the raw file in the repo
              RAW_LINK="https://raw.githubusercontent.com/${REPO_FULL_NAME}/main/feeds/images/$hash_name"
              
              # Get file size for the enclosure tag
              FILE_SIZE=$(stat -c%s "$local_path")
              
              # Swap old URLs with local GitHub links
              sed -i "s|$img_url|$RAW_LINK|g" "$TMP_FILE"
              
              # Inject enclosure tags before the item closing tag for better reader support
              ENCLOSURE_TAG="<enclosure url=\"$RAW_LINK\" type=\"image/jpeg\" length=\"$FILE_SIZE\" />"
              sed -i "s|</item>|$ENCLOSURE_TAG</item>|g" "$TMP_FILE"
          fi
      done
      mv "$TMP_FILE" "feeds/$SLUG.xml"
    fi
done

# Update index for next rotation
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

# Run local optimizations
[[ -f "optimizer.py" ]] && python3 optimizer.py

# Keep the repo light; purge images older than 3 days
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;

# Push changes to origin
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: fix image visibility using enclosure tags" && git push
