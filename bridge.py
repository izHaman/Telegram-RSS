import os
import asyncio
import hashlib
from telethon import TelegramClient
from telethon.sessions import StringSession
from PIL import Image  # Professional image compression

# Environment configuration
API_ID = int(os.environ.get("TELEGRAM_API_ID"))
API_HASH = os.environ.get("TELEGRAM_API_HASH")
SESSION = os.environ.get("TELEGRAM_SESSION")

CHANNELS = ["mamlekate", "vahidonline", "iranintltv", "dw_farsi"]

async def download_and_optimize():
    async with TelegramClient(StringSession(SESSION), API_ID, API_HASH) as client:
        print("Connected. Syncing media with optimization...")
        
        for channel in CHANNELS:
            async for message in client.iter_messages(channel, limit=8):
                if message.media:
                    # Generate unique MD5 hash for filename consistency
                    unique_str = f"{message.id}_{channel}"
                    raw_hash = hashlib.md5(unique_str.encode()).hexdigest()
                    
                    # Determine extension and paths
                    is_video = hasattr(message.media, 'document') and "video" in (message.media.document.mime_type or "")
                    ext = "mp4" if is_video else "jpg"
                    path = f"feeds/media/{raw_hash}.{ext}"
                    
                    if not os.path.exists(path):
                        print(f"Downloading: {path}")
                        await message.download_media(file=path)
                        
                        # --- Integrated Optimization Logic ---
                        if ext == "jpg":
                            try:
                                with Image.open(path) as img:
                                    # Convert to RGB if necessary and compress
                                    img = img.convert("RGB")
                                    # professional level compression (quality 70 is sweet spot)
                                    img.save(path, "JPEG", quality=70, optimize=True)
                                    print(f"Optimized: {path}")
                            except Exception as e:
                                print(f"Optimization failed for {path}: {e}")

if __name__ == "__main__":
    os.makedirs("feeds/media", exist_ok=True)
    asyncio.run(download_and_optimize())
