#!/bin/bash

RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main"
PLACEHOLDER_URL="${RAW_BASE_URL}/feeds/media/default_img/text_placeholder.jpg"

[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

python bridge.py

RSSHUB_INSTANCES=(
    "https://rsshub.rssforever.com"
    "https://rsshub.moeyy.cn"
    "https://rsshub.app"
)

CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

mkdir -p feeds/media/default_img

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    for INSTANCE in "${RSSHUB_INSTANCES[@]}"; do
        curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "$INSTANCE/telegram/channel/$SLUG?include_video=1" --connect-timeout 15 --max-time 60
        if grep -qiP "(item|channel)" "$TMP_FILE"; then break; fi
    done

    if [[ -s "$TMP_FILE" ]]; then
        urls=$(grep -oP 'https://[^\s"<]+\.(mp4|mkv|mov|mp3|jpg|jpeg|png|gif|webp|telesco\.pe/file/[^"<\s?]*)' "$TMP_FILE" | sort -u)
        
        for media_url in $urls; do
            clean_url=$(echo "$media_url" | sed 's/&amp;/\&/g' | cut -d'?' -f1)
            
            if [[ "$clean_url" =~ t\.me/([^/]+)/([0-9]+) ]]; then
                canonical_url="https://t.me/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
                raw_hash=$(echo -n "$canonical_url" | md5sum | cut -d' ' -f1)
            else
                raw_hash=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1)
            fi
            
            existing_file=$(find feeds/media -maxdepth 1 -name "$raw_hash.*" | grep -v "\.tmp$" | grep -v "\.thumb\.jpg$" | head -n 1)
            
            if [[ -n "$existing_file" ]]; then
                ext="${existing_file##*.}"
                RAW_LINK="${RAW_BASE_URL}/feeds/media/${raw_hash}.${ext}"
                sed -i "s|$media_url|$RAW_LINK|g" "$TMP_FILE"
            fi
        done
        
        perl processor.pl "$PLACEHOLDER_URL" < "$TMP_FILE" > "$TMP_FILE.processed"
        [[ -s "$TMP_FILE.processed" ]] && mv "$TMP_FILE.processed" "feeds/$SLUG.xml"
        rm -f "$TMP_FILE" "$TMP_FILE.processed"
    fi
done

NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json
find feeds/media -maxdepth 1 -type f -mmin +2880 -exec rm -f {} \;

git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: updated feeds with localized media" && git push
