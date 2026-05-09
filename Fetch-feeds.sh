#!/bin/bash

# Dynamic repo detection
REPO_FULL_NAME=$GITHUB_REPOSITORY
# Path to your custom placeholder image
PLACEHOLDER_URL="https://raw.githubusercontent.com/${REPO_FULL_NAME}/main/feeds/images/default_img/text_placeholder.jpg"

# Handle channel rotation state
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

# Updated channel list (drtel included)
CHANNELS=("mamlekate" "ircfspace" "vahidonline" "iranintltv" "drtel" "hatricktv" "iholymaryat70" "jadivarlog" "digitechirchannel" "whynationsfail2019" "khateraaat" "dw_farsi")
TOTAL=${#CHANNELS[@]}
CHUNK_SIZE=4 

mkdir -p feeds/images/default_img

for (( i=0; i<$CHUNK_SIZE; i++ )); do
    CURR_IDX=$(( (INDEX + i) % TOTAL ))
    SLUG="${CHANNELS[$CURR_IDX]}"
    TMP_FILE="feeds/$SLUG.xml.tmp"
    
    # Fetch feed from RSSHub
    curl -L -s -o "$TMP_FILE" -A "Mozilla/5.0" "https://rsshub.rssforever.com/telegram/channel/$SLUG" --max-time 60

    if [[ -s "$TMP_FILE" ]]; then
        # Create a clean version of the XML
        NEW_FILE="feeds/$SLUG.xml"
        
        # We'll use a temporary file to process each <item> block
        # Using a perl one-liner for reliable multi-line item processing
        perl -i -0777 -pe 's/<item>(.*?)<\/item>/
            my $content = $1;
            if ($content =~ /https:\/\/(cdn[0-9]*\.telesco\.pe|telesco\.pe)\/file\/([^"<\s?]*)/) {
                # This item HAS an image, let it be processed later or here
                $content;
            } else {
                # This is a text-only item, inject the placeholder enclosure
                $content . "<enclosure url=\"'${PLACEHOLDER_URL}'\" type=\"image\/jpeg\" length=\"0\" \/>";
            }
            "<item>" . $content . "<\/item>"
        /gs' "$TMP_FILE"

        # Now handle existing Telegram images
        urls=$(grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s?]*' "$TMP_FILE" | sort -u)
        
        for img_url in $urls; do
            clean_url=$(echo "$img_url" | cut -d'?' -f1)
            hash_name=$(echo -n "$clean_url" | md5sum | cut -d' ' -f1).jpg
            local_path="feeds/images/$hash_name"
            
            if [[ ! -f "$local_path" ]]; then
                curl -s -L --max-filesize 10M -o "$local_path" "$img_url" --max-time 20
            fi
            
            if [[ -f "$local_path" ]]; then
                TIMESTAMP=$(date +%s)
                RAW_LINK="https://raw.githubusercontent.com/${REPO_FULL_NAME}/main/feeds/images/${hash_name}?v=${TIMESTAMP}"
                FILE_SIZE=$(stat -c%s "$local_path")
                
                # Replace URL in body and add enclosure
                sed -i "s|$img_url|$RAW_LINK|g" "$TMP_FILE"
                # Add enclosure for these images too (if not already present)
                sed -i "s|</item>|<enclosure url=\"$RAW_LINK\" type=\"image/jpeg\" length=\"$FILE_SIZE\" /></item>|g" "$TMP_FILE"
            fi
        done
        mv "$TMP_FILE" "$NEW_FILE"
    fi
done

# Update rotation index
NEXT_INDEX=$(( (INDEX + CHUNK_SIZE) % TOTAL ))
echo "{\"index\": $NEXT_INDEX}" > state.json

# Cleanup and push
[[ -f "optimizer.py" ]] && python3 optimizer.py
# Clean only the cached images, NOT the default_img folder
find feeds/images -maxdepth 1 -name "*.jpg" -mtime +3 -exec rm {} \;

git config --global user.name "github-actions[bot]"
git config --global user.email "github-actions[bot]@users.noreply.github.com"
git add .
git commit -m "sync: enhance feeds with text-only placeholders" && git push
