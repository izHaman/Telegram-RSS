import os
import asyncio
import hashlib
from telethon import TelegramClient
from telethon.sessions import StringSession
from PIL import Image

# Professional Media Bridge with Thumbnail Extraction Support
API_ID = int(os.environ.get("TELEGRAM_API_ID", 0))
API_HASH = os.environ.get("TELEGRAM_API_HASH", "")
SESSION = os.environ.get("TELEGRAM_SESSION", "")

CHANNELS = ["mamlekate", "ircfspace", "vahidonline", "iranintltv", "dw_farsi"]

async def process_media_hub():
    """
    Connects to Telegram, downloads media, and extracts thumbnails for non-image files.
    Ensures Feeder has a visual preview for every post.
    """
    if not all([API_ID, API_HASH, SESSION]):
        return

    async with TelegramClient(StringSession(SESSION), API_ID, API_HASH) as client:
        print("Connected. Extracting media and thumbnails...")
        
        for channel in CHANNELS:
            async for message in client.iter_messages(channel, limit=10):
                if message.media:
                    # Consistent MD5 hashing based on Telegram message URL
                    clean_url = f"https://t.me/{channel}/{message.id}"
                    raw_hash = hashlib.md5(clean_url.encode()).hexdigest()
                    
                    # Detect media type
                    is_video = hasattr(message.media, 'document') and "video" in (message.media.document.mime_type or "")
                    is_audio = hasattr(message.media, 'document') and "audio" in (message.media.document.mime_type or "")
                    
                    ext = "mp4" if is_video else "mp3" if is_audio else "jpg"
                    file_path = f"feeds/media/{raw_hash}.{ext}"
                    thumb_path = f"feeds/media/{raw_hash}.thumb.jpg"

                    # 1. Download primary media if not exists
                    if not os.path.exists(file_path):
                        print(f"Downloading: {ext.upper()} -> {raw_hash}")
                        await message.download_media(file=file_path)

                    # 2. Extract and optimize thumbnail for Videos/Audio
                    if (is_video or is_audio) and not os.path.exists(thumb_path):
                        print(f"Extracting thumbnail for {ext}...")
                        # Telethon extracts video thumbs automatically with thumb=-1
                        await message.download_media(file=thumb_path, thumb=-1 if is_video else None)
                        
                        # Verify if thumb was created, else use a placeholder or generic icon logic in Perl
                        if os.path.exists(thumb_path):
                            try:
                                with Image.open(thumb_path) as img:
                                    img.convert("RGB").save(thumb_path, "JPEG", quality=60, optimize=True)
                            except:
                                pass

if __name__ == "__main__":
    os.makedirs("feeds/media", exist_ok=True)
    asyncio.run(process_media_hub())
