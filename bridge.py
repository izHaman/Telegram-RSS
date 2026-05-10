import os
import asyncio
import hashlib
from telethon import TelegramClient
from telethon.sessions import StringSession
from PIL import Image

# --- Configuration & Secrets ---
# Fetched from GitHub Repository Secrets
API_ID = int(os.environ.get("TELEGRAM_API_ID", 0))
API_HASH = os.environ.get("TELEGRAM_API_HASH", "")
SESSION = os.environ.get("TELEGRAM_SESSION", "")

# List of target channels for direct high-speed media extraction
CHANNELS = ["mamlekate", "ircfspace", "vahidonline", "iranintltv", "dw_farsi"]

async def process_telegram_bridge():
    """
    Connects to Telegram using a Session String and fetches recent media.
    Directly bypasses RSSHub limitations for media availability.
    """
    if not all([API_ID, API_HASH, SESSION]):
        print("Missing Telegram Secrets. Skipping Bridge execution.")
        return

    async with TelegramClient(StringSession(SESSION), API_ID, API_HASH) as client:
        print("Telegram Bridge: Authentication successful.")
        
        for channel in CHANNELS:
            print(f"Syncing media from: @{channel}")
            # Fetch last 10 messages to ensure no media is missed between runs
            async for message in client.iter_messages(channel, limit=10):
                if message.media:
                    # Construct the canonical Telegram URL for MD5 hashing (matches Bash logic)
                    clean_url = f"https://t.me/{channel}/{message.id}"
                    raw_hash = hashlib.md5(clean_url.encode()).hexdigest()
                    
                    # Determine file extension and MIME category
                    is_video = hasattr(message.media, 'document') and "video" in (message.media.document.mime_type or "")
                    ext = "mp4" if is_video else "jpg"
                    file_path = f"feeds/media/{raw_hash}.{ext}"
                    
                    # Download only if the file doesn't already exist in the repository
                    if not os.path.exists(file_path):
                        print(f"Downloading new media: {raw_hash}.{ext}")
                        await message.download_media(file=file_path)
                        
                        # Apply Image Optimization (replaces standalone Optimizer.py)
                        if ext == "jpg":
                            try:
                                with Image.open(file_path) as img:
                                    img = img.convert("RGB")
                                    # Save with professional compression settings (70% quality)
                                    img.save(file_path, "JPEG", quality=70, optimize=True)
                                    print(f"Optimized image: {raw_hash}.jpg")
                            except Exception as e:
                                print(f"Optimization error for {file_path}: {e}")

if __name__ == "__main__":
    # Ensure the media directory exists before starting
    os.makedirs("feeds/media", exist_ok=True)
    asyncio.run(process_telegram_bridge())
