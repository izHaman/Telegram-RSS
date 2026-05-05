#!/bin/bash

# --- 1. State Persistence (Round-robin logic) ---
[[ ! -f "state.json" ]] && echo '{"index": 0}' > state.json
INDEX=$(grep -oP '"index": \K[0-9]+' state.json)

CHANNELS=(
  "mamlekate" "ircfspace" "vahidonline" "iranintltv"
  "persian_rockstar" "hatricktv" "iholymaryat70"
  "jadivarlog" "digitechirchannel" "whynationsfail2019"
  "khateraaat" "dw_farsi"
)

TOTAL=${#CHANNELS[@]}
SLUG="${CHANNELS[$INDEX]}"
NEXT_INDEX=$(( (INDEX + 1) % TOTAL ))

echo "[$(($INDEX + 1))/$TOTAL] Syncing: $SLUG"

# --- 2. Environment Setup ---
mkdir -p feeds/images

# --- 3. Remote Fetch ---
BASE_URL="https://rsshub.rssforever.com/telegram/channel"
TMP_FILE="feeds/$SLUG.xml.tmp"

HTTP_CODE=$(curl -L -s -o "$TMP_FILE" -w "%{http_code}" \
  "$BASE_URL/$SLUG" --max-time 60 --connect-timeout 15 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" != "200" ]] || [[ ! -s "$TMP_FILE" ]]; then
  echo "  ! Fetch failed (HTTP $HTTP_CODE). Aborting."
  rm -f "$TMP_FILE"
else
  # --- 4. Media Mirroring (GitHub CDN Proxy) ---
  echo "  > Mirroring media to local storage..."
  
  # Extract and download unique Telegram media links
  grep -oP 'https://(cdn[0-9]*\.telesco\.pe|telesco\.pe)/file/[^"<\s]*' "$TMP_FILE" | sort -u | while read -r img_url; do
      hash_name=$(echo -n "$img_url" | md5sum | cut -d' ' -f1).jpg
      local_path="feeds/images/$hash_name"
      
      if [[ ! -f "$local_path" ]]; then
          curl -s -L --max-filesize 5M -o "$local_path" "$img_url" --max-time 15
      fi
      
      # Rewrite URLs to point to GitHub Raw CDN
      CDN_URL="https://raw.githubusercontent.com/izHaman/Telegram-SSR/main/feeds/images/$hash_name"
      sed -i "s|$img_url|$CDN_URL|g" "$TMP_FILE"
  done

  # --- 5. Atomic Update (Content-aware diff) ---
  if [[ -f "feeds/$SLUG.xml" ]]; then
    # Ignore volatile metadata like build dates to prevent redundant commits
    if diff -I '<lastBuildDate>' -I '<pubDate>' -I '<updated>' "feeds/$SLUG.xml" "$TMP_FILE" > /dev/null; then
      echo "  = No significant changes. Skipping."
      rm "$TMP_FILE"
    else
      mv "$TMP_FILE" "feeds/$SLUG.xml"
      echo "  + Feed updated."
    fi
  else
    mv "$TMP_FILE" "feeds/$SLUG.xml"
  fi
fi

# --- 6. Quota Management (Retention policy) ---
# Keep only the last 72 hours of media to stay within repo size limits
find feeds/images -name "*.jpg" -mtime +3 -exec rm {} \;

# --- 7. Persistence and VCS Push ---
echo "{\"index\": $NEXT_INDEX}" > state.json

git config --global user.name "gh-actions-bot"
git config --global user.email "actions@github.com"
git add feeds/*.xml feeds/images/*.jpg state.json

if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "chore: sync $SLUG @ $(date -u +'%Y-%m-%d %H:%M') UTC"
  git push
  echo "  # Changes pushed to origin."
else
  echo "  # Workspace clean."
fi
