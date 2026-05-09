#!/bin/bash

# Repository configuration
REPO_FULL_NAME=$GITHUB_REPOSITORY
PLACEHOLDER_URL="https://raw.githubusercontent.com/${REPO_FULL_NAME}/main/feeds/images/default_img/text_placeholder.jpg"

# Handle rotation state
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
    
    # Fetch raw feed content
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
        urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
        
        for media_url in $urls; do
            clean_url=$(echo "$media_url" | cut -d'?' -f1)
            raw_hash=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1)
            
            # Check if file exists (ignoring extensions) to prevent redundant downloads
            existing_file=$(find feeds/images -maxdepth 1 -name "$raw_hash.*" | grep -v "\.tmp$" | head -n 1)
            
            if [[ -z "$existing_file" ]]; then
                temp_path="feeds/images/$raw_hash.tmp"
                curl -s -L --max-filesize 20M -o "$temp_path" "$media_url" --max-time 40
                
                if [[ -s "$temp_path" ]]; then
                    # Detect the true media format via magic bytes
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
                    continue # Skip current iteration if file is too large or download failed
                fi
            else
                local_path="$existing_file"
                ext="${local_path##*.}"
            fi
            
            # Direct raw link generation using standard, unfiltered domain
            TIMESTAMP=$(date +%s)
            RAW_LINK="https://raw.githubusercontent.com/${REPO_FULL_NAME}/main/feeds/images/${raw_hash}.${ext}?v=${TIMESTAMP}"
            
            # Swap media URLs inside the XML body
            sed -i "s|$media_url|$RAW_LINK|g" "$TMP_FILE"
        done
        
        # Run Perl processor to handle enclosures
        perl processor.pl "$PLACEHOLDER_URL" < "$TMP_FILE" > "$TMP_FILE.processed"
        
        # SAFETY CHECK: Only overwrite the actual feed if the output is not empty
        if [[ -s "$TMP_FILE.processed" ]]; then
            mv "$TMP_FILE.processed" "feeds/$SLUG.xml"
        else
            echo "Error: Perl processor returned empty output for $SLUG. Rollback triggered."
            mv "$TMP_FILE" "feeds/$SLUG.xml"
        fi
        rm -f "$TMP_FILE" "$TMP_FILE.processed"
    fi
done

NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

[[ -f "optimizer.py" ]] && python3 optimizer.py

# Nuke any cached media asset older than exactly 48 hours (2880 mins)
find feeds/images -maxdepth 1 -type f -mmin +2880 -exec rm -f {} \;

git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: resolve empty feeds, revert domain, and secure file processing" && git push
