#!/bin/bash

REPO_FULL_NAME=$GITHUB_REPOSITORY
PLACEHOLDER_URL="https://raw.githubusercontent.com/${REPO_FULL_NAME}/main/feeds/images/default_img/text_placeholder.jpg"

[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

mkdir -p feeds/images/default_img

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    # Fetch original feed
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
        urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
        counter=0
        
        for media_url in $urls; do
            clean_url=$(echo "$media_url" | cut -d'?' -f1)
            raw_hash=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1)
            
            # Check if file exists (ignoring extensions) to prevent re-download
            existing_file=$(find feeds/images -maxdepth 1 -name "$raw_hash.*" | grep -v "\.tmp$" | head -n 1)
            
            if [[ -z "$existing_file" ]]; then
                temp_path="feeds/images/$raw_hash.tmp"
                curl -s -L --max-filesize 20M -o "$temp_path" "$media_url" --max-time 40
                
                if [[ -s "$temp_path" ]]; then
                    # Magic byte detection to find the TRUE file type
                    mime=$(file -b --mime-type "$temp_path")
                    case "$mime" in
                        video/mp4) ext="mp4" ;;
                        video/x-matroska) ext="mkv" ;;
                        audio/mpeg) ext="mp3" ;;
                        audio/ogg) ext="ogg" ;;
                        image/jpeg) ext="jpg" ;;
                        image/png) ext="png" ;;
                        image/gif) ext="gif" ;;
                        image/webp) ext="webp" ;;
                        application/pdf) ext="pdf" ;;
                        *) ext="bin" ;;
                    esac
                    
                    local_path="feeds/images/$raw_hash.$ext"
                    mv "$temp_path" "$local_path"
                else
                    rm -f "$temp_path"
                    continue # Skip if curl failed or file is > 20MB
                fi
            else
                local_path="$existing_file"
                ext="${local_path##*.}"
            fi
            
            # Domain balancing
            if (( counter % 2 == 0 )); then
                DOMAIN="raw.githubusercontent.com"
            else
                DOMAIN="raw.githubusercontents.com"
            fi
            ((counter++))
            
            TIMESTAMP=$(date +%s)
            RAW_LINK="https://${DOMAIN}/${REPO_FULL_NAME}/main/feeds/images/${raw_hash}.${ext}?v=${TIMESTAMP}"
            
            # ONLY swap the raw URL in the text body here. No enclosures yet.
            sed -i "s|$media_url|$RAW_LINK|g" "$TMP_FILE"
        done
        
        # Finally, let Perl handle the enclosures properly per <item>
        cat "$TMP_FILE" | perl processor.pl "$PLACEHOLDER_URL" > "$TMP_FILE.processed"
        mv "$TMP_FILE.processed" "feeds/$SLUG.xml"
        rm -f "$TMP_FILE"
    fi
done

NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

[[ -f "optimizer.py" ]] && python3 optimizer.py

# Strict 48h purge (2880 mins)
find feeds/images -maxdepth 1 -type f -mmin +2880 -exec rm -f {} \;

git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: true mime detection and accurate enclosure routing" && git push
