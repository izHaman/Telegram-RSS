#!/bin/bash

RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main"
PLACEHOLDER_URL="${RAW_BASE_URL}/feeds/media/default_img/text_placeholder.jpg"

[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

mkdir -p feeds/media/default_img

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --connect-timeout 15 --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
        urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
        
        for media_url in $urls; do
            clean_url=$(echo "$media_url" | cut -d'?' -f1)
            raw_hash=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1)
            
            existing_file=$(find feeds/media -maxdepth 1 -name "$raw_hash.*" | grep -v "\.tmp$" | head -n 1)
            
            if [[ -z "$existing_file" ]]; then
                temp_path="feeds/media/$raw_hash.tmp"
                # Increased filesize to 30MB to accommodate better quality videos
                curl -s -L -o "$temp_path" "$media_url" --connect-timeout 15 --max-time 60 --max-filesize 30M
                
                if [[ -s "$temp_path" ]] && ! grep -qi "<html>" "$temp_path"; then
                    mime=$(file -b --mime-type "$temp_path")
                    case "$mime" in
                        video/mp4) ext="mp4" ;;
                        video/x-matroska) ext="mkv" ;;
                        video/quicktime) ext="mov" ;;
                        audio/mpeg) ext="mp3" ;;
                        audio/ogg) ext="ogg" ;;
                        image/jpeg) ext="jpg" ;;
                        image/png) ext="png" ;;
                        image/gif) ext="gif" ;;
                        image/webp) ext="webp" ;;
                        *) rm -f "$temp_path"; continue ;;
                    esac
                    
                    local_path="feeds/media/$raw_hash.$ext"
                    mv "$temp_path" "$local_path"
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

# Cleanup and Commit
find feeds/media -maxdepth 1 -type f -mmin +2880 -exec rm -f {} \;
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: enhanced video support and enclosure injection" && git push
