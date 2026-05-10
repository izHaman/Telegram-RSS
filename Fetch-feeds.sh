#!/bin/bash

# Configuration for GitHub Raw content and Fallback assets
RAW_BASE_URL="https://raw.githubusercontent.com/${GITHUB_REPOSITORY}/main"
PLACEHOLDER_URL="${RAW_BASE_URL}/feeds/media/default_img/text_placeholder.jpg"

# Maintain persistence for channel rotation via state.json
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

# Execute the Telegram Bridge to pre-fetch media directly from MTProto
# This ensures media is available locally before RSSHub processing
echo "Step 1: Running Telegram Media Bridge..."
python bridge.py

# RSSHub Instances for metadata and fallback content
RSSHUB_INSTANCES=(
    "https://rsshub.rssforever.com"
    "https://rsshub.moeyy.cn"
    "https://rsshub.app"
)

CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

mkdir -p feeds/media/default_img

echo "Step 2: Processing RSSHub Feed Chunk..."
for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    for INSTANCE in "${RSSHUB_INSTANCES[@]}"; do
        curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "$INSTANCE/telegram/channel/$SLUG?include_video=1" --connect-timeout 15 --max-time 60
        if grep -qiP "(mp4|video|telesco\.pe)" "$TMP_FILE"; then break; fi
    done

    if [[ -s "$TMP_FILE" ]]; then
        # Identify and localize media links found in the XML content
        urls=$(grep -oP 'https://[^\s"<]+\.(mp4|mkv|mov|mp3|jpg|jpeg|png|gif|webp|telesco\.pe/file/[^"<\s?]*)' "$TMP_FILE" | sort -u)
        
        for media_url in $urls; do
            clean_url=$(echo "$media_url" | cut -d'?' -f1 | sed 's/&amp;/\&/g')
            raw_hash=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1)
            
            existing_file=$(find feeds/media -maxdepth 1 -name "$raw_hash.*" | grep -v "\.tmp$" | head -n 1)
            
            # If the bridge didn't catch it, attempt standard download
            if [[ -z "$existing_file" ]]; then
                temp_path="feeds/media/$raw_hash.tmp"
                curl -s -L -A "Mozilla/5.0" -H "Referer: https://t.me/" --max-filesize 30M -o "$temp_path" "$media_url" --connect-timeout 15 --max-time 45
                
                if [[ -s "$temp_path" ]] && ! grep -qiP "(<html>|404 Not Found)" "$temp_path"; then
                    mime=$(file -b --mime-type "$temp_path")
                    ext="jpg"
                    [[ "$mime" == "video/mp4" ]] && ext="mp4"
                    mv "$temp_path" "feeds/media/$raw_hash.$ext"
                else
                    rm -f "$temp_path"
                    continue
                fi
                local_path="feeds/media/$raw_hash.$ext"
            else
                local_path="$existing_file"
                ext="${local_path##*.}"
            fi
            
            # Replace remote links with local GitHub raw links
            if [[ -n "$ext" ]]; then
                TIMESTAMP=$(date +%s)
                RAW_LINK="${RAW_BASE_URL}/feeds/media/${raw_hash}.${ext}?v=${TIMESTAMP}"
                sed -i "s|$media_url|$RAW_LINK|g" "$TMP_FILE"
            fi
        done
        
        # Inject placeholders for text-only posts using the Perl Processor
        perl processor.pl "$PLACEHOLDER_URL" < "$TMP_FILE" > "$TMP_FILE.processed"
        [[ -s "$TMP_FILE.processed" ]] && mv "$TMP_FILE.processed" "feeds/$SLUG.xml"
        rm -f "$TMP_FILE" "$TMP_FILE.processed"
    fi
done

# Maintenance: Cleanup and State Update
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json
find feeds/media -maxdepth 1 -type f -mmin +2880 -exec rm -f {} \;

# Commit and Push the updated datasets
git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: integrated telethon bridge and media optimization" && git push
