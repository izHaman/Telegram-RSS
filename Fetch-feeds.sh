#!/bin/bash

# Repository assets configuration
RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main"
PLACEHOLDER_URL="${RAW_BASE_URL}/feeds/media/default_img/text_placeholder.jpg"

# Persistence and rotation handling
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

# Initialize environment
mkdir -p feeds/media/default_img
if [[ ! -f "feeds/media/default_img/text_placeholder.jpg" ]]; then
    curl -s -L -o "feeds/media/default_img/text_placeholder.jpg" "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?q=80&w=600&auto=format&fit=crop"
fi

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    # Ingest upstream feed
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
        urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
        
        for media_url in $urls; do
            clean_url=$(echo "$media_url" | cut -d'?' -f1)
            raw_hash=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1)
            
            # Prevent redundant downloads
            existing_file=$(find feeds/media -maxdepth 1 -name "$raw_hash.*" | grep -v "\.tmp$" | head -n 1)
            
            if [[ -z "$existing_file" ]]; then
                temp_path="feeds/media/$raw_hash.tmp"
                curl -s -L --max-filesize 20M -o "$temp_path" "$media_url" --max-time 40
                
                if [[ -s "$temp_path" ]]; then
                    # Dynamic MIME detection
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
            
            # Build cache-busting raw link
            TIMESTAMP=$(date +%s)
            RAW_LINK="${RAW_BASE_URL}/feeds/media/${raw_hash}.${ext}?v=${TIMESTAMP}"
            sed -i "s|$media_url|$RAW_LINK|g" "$TMP_FILE"
        done
        
        # Inject enclosures for media support
        perl processor.pl "$PLACEHOLDER_URL" < "$TMP_FILE" > "$TMP_FILE.processed"
        
        if [[ -s "$TMP_FILE.processed" ]]; then
            mv "$TMP_FILE.processed" "feeds/$SLUG.xml"
        else
            mv "$TMP_FILE" "feeds/$SLUG.xml"
        fi
        rm -f "$TMP_FILE" "$TMP_FILE.processed"
    fi
done

# Update rotation state
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

[[ -f "optimizer.py" ]] && python3 optimizer.py

# Cleanup stale media (48h retention)
find feeds/media -maxdepth 1 -type f -mmin +2880 -exec rm -f {} \;

# Commit synchronized changes
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: update feeds and media assets" && git push
