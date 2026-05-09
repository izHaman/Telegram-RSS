#!/bin/bash

# Repo config
REPO_FULL_NAME=$GITHUB_REPOSITORY
PLACEHOLDER_URL="https://raw.githubusercontent.com/${REPO_FULL_NAME}/main/feeds/images/default_img/text_placeholder.jpg"

# Load rotation state
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

# Channel list
CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

mkdir -p feeds/images/default_img

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    # Grab raw RSS from upstream
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
        # 1. Pass through Perl processor to ensure text-only items get the placeholder
        cat "$TMP_FILE" | perl processor.pl "$PLACEHOLDER_URL" > "$TMP_FILE.processed"
        mv "$TMP_FILE.processed" "$TMP_FILE"

        # 2. Extract ALL media links (images, videos, audio, docs)
        urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
        
        counter=0
        
        for media_url in $urls; do
            clean_url=$(echo "$media_url" | cut -d'?' -f1)
            
            # Dynamically extract extension (e.g., mp4, mp3, jpg)
            ext="${clean_url##*.}"
            # Fallback to .bin if no extension is found in the URL
            [[ "$ext" == "$clean_url" ]] && ext="bin"
            
            # Hash the filename but keep the original extension
            hash_name=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1).${ext}
            local_path="feeds/images/$hash_name"
            
            # Pull media with a strict 20MB limit
            if [[ ! -f "$local_path" ]]; then
                curl -s -L --max-filesize 20M -o "$local_path" "$media_url" --max-time 40
            fi
            
            # Only proceed if download was successful (and skipped files > 20MB are ignored)
            if [[ -s "$local_path" ]]; then
                # Map extensions to proper MIME types for XML enclosures
                case "${ext,,}" in
                    mp4|mkv|avi) mime="video/mp4" ;;
                    mp3|m4a|wav) mime="audio/mpeg" ;;
                    ogg|oga)     mime="audio/ogg" ;;
                    jpg|jpeg)    mime="image/jpeg" ;;
                    png)         mime="image/png" ;;
                    gif)         mime="image/gif" ;;
                    pdf)         mime="application/pdf" ;;
                    *)           mime="application/octet-stream" ;;
                esac

                # Load balance across mirrors
                if (( counter % 2 == 0 )); then
                    DOMAIN="raw.githubusercontent.com"
                else
                    DOMAIN="raw.githubusercontents.com"
                fi
                ((counter++))

                TIMESTAMP=$(date +%s)
                RAW_LINK="https://${DOMAIN}/${REPO_FULL_NAME}/main/feeds/images/${hash_name}?v=${TIMESTAMP}"
                FILE_SIZE=$(stat -c%s "$local_path")
                
                # Replace the raw URL in the post body
                sed -i "s|$media_url|$RAW_LINK|g" "$TMP_FILE"
                
                # Swap the text-only placeholder enclosure with the actual rich media enclosure
                sed -i "s|<enclosure url=\"$PLACEHOLDER_URL\" type=\"image/jpeg\" length=\"0\" />|<enclosure url=\"$RAW_LINK\" type=\"$mime\" length=\"$FILE_SIZE\" />|g" "$TMP_FILE"
            else
                # Clean up empty files if curl failed or hit the 20MB limit
                [[ -f "$local_path" ]] && rm -f "$local_path"
            fi
        done
        mv "$TMP_FILE" "feeds/$SLUG.xml"
    fi
done

# Shift rotation index
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

# Optional: Run custom optimizations
[[ -f "optimizer.py" ]] && python3 optimizer.py

# Aggressive cleanup: Nuke any media older than exactly 48 hours (2880 mins)
# -maxdepth 1 prevents it from deleting your placeholder in /default_img/
find feeds/images -maxdepth 1 -type f -mmin +2880 -exec rm -f {} \;

# Push artifacts to upstream
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: fetch rich media (<20MB) & strict 48h purge" && git push
