#!/bin/bash

RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main"
PLACEHOLDER_URL="${RAW_BASE_URL}/feeds/media/default_img/text_placeholder.jpg"

[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

# Using a different instance for testing if the first one fails
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
    
    # Try multiple instances if one doesn't provide media
    for INSTANCE in "${RSSHUB_INSTANCES[@]}"; do
        # We add ?include_video=1 to force the instance to provide video links
        curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "$INSTANCE/telegram/channel/$SLUG?include_video=1" --connect-timeout 15 --max-time 60
        if grep -qiP "(mp4|video|telesco\.pe)" "$TMP_FILE"; then break; fi
    done

    if [[ -s "$TMP_FILE" ]]; then
        # Expanded regex to catch all possible media links
        urls=$(grep -oP 'https://[^\s"<]+\.(mp4|mkv|mov|mp3|jpg|jpeg|png|gif|webp|telesco\.pe/file/[^"<\s?]*)' "$TMP_FILE" | sort -u)
        
        for media_url in $urls; do
            clean_url=$(echo "$media_url" | cut -d'?' -f1 | sed 's/&amp;/\&/g')
            raw_hash=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1)
            
            existing_file=$(find feeds/media -maxdepth 1 -name "$raw_hash.*" | grep -v "\.tmp$" | head -n 1)
            
            if [[ -z "$existing_file" ]]; then
                temp_path="feeds/media/$raw_hash.tmp"
                
                # Fetch with maximum browser-like headers
                curl -s -L \
                    -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36" \
                    -H "Referer: https://t.me/" \
                    --max-filesize 30M \
                    -o "$temp_path" "$media_url" --connect-timeout 15 --max-time 45
                
                if [[ -s "$temp_path" ]] && ! grep -qiP "(<html>|404 Not Found|nginx|forbidden|access denied)" "$temp_path"; then
                    mime=$(file -b --mime-type "$temp_path")
                    ext=""
                    case "$mime" in
                        video/mp4) ext="mp4" ;;
                        video/x-matroska) ext="mkv" ;;
                        audio/mpeg) ext="mp3" ;;
                        image/jpeg) ext="jpg" ;;
                        image/png) ext="png" ;;
                        image/gif) ext="gif" ;;
                        image/webp) ext="webp" ;;
                        *) 
                           # If mime fails but URL has extension, trust the URL
                           if [[ "$clean_url" =~ \.(mp4|mkv|mp3|jpg|png|gif)$ ]]; then
                               ext="${BASH_REMATCH[1]}"
                           else
                               rm -f "$temp_path"; continue
                           fi
                           ;;
                    esac
                    
                    mv "$temp_path" "feeds/media/$raw_hash.$ext"
                    local_path="feeds/media/$raw_hash.$ext"
                else
                    rm -f "$temp_path"
                    continue
                fi
            else
                local_path="$existing_file"
                ext="${local_path##*.}"
            fi
            
            if [[ -n "$ext" ]]; then
                TIMESTAMP=$(date +%s)
                RAW_LINK="${RAW_BASE_URL}/feeds/media/${raw_hash}.${ext}?v=${TIMESTAMP}"
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
git commit -m "sync: aggressive media extraction and bypass fix" && git push
