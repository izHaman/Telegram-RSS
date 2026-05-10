import os, asyncio, hashlib
from telethon import TelegramClient
from telethon.sessions import StringSession
from PIL import Image

API_ID = int(os.environ.get("TELEGRAM_API_ID", 0))
API_HASH = os.environ.get("TELEGRAM_API_HASH", "")
SESSION = os.environ.get("TELEGRAM_SESSION", "")
CHANNELS = ["mamlekate", "ircfspace", "vahidonline", "iranintltv", "dw_farsi"]

async def process_media_hub():
    if not all([API_ID, API_HASH, SESSION]): return
    async with TelegramClient(StringSession(SESSION), API_ID, API_HASH) as client:
        for channel in CHANNELS:
            async for message in client.iter_messages(channel, limit=10):
                if message.media:
                    media_url = f"https://t.me/{channel}/{message.id}"
                    raw_hash = hashlib.md5(media_url.encode()).hexdigest()
                    
                    is_video = hasattr(message.media, 'document') and "video" in (message.media.document.mime_type or "")
                    is_audio = hasattr(message.media, 'document') and "audio" in (message.media.document.mime_type or "")
                    
                    ext = "mp4" if is_video else "mp3" if is_audio else "jpg"
                    file_path = f"feeds/media/{raw_hash}.{ext}"
                    thumb_path = f"feeds/media/{raw_hash}.thumb.jpg"

                    if not os.path.exists(file_path):
                        await message.download_media(file=file_path)

                    if (is_video or is_audio) and not os.path.exists(thumb_path):
                        await message.download_media(file=thumb_path, thumb=-1 if is_video else None)
                        if os.path.exists(thumb_path):
                            try:
                                with Image.open(thumb_path) as img:
                                    img.convert("RGB").save(thumb_path, "JPEG", quality=60)
                            except:
                                pass

if __name__ == "__main__":
    os.makedirs("feeds/media", exist_ok=True)
    asyncio.run(process_media_hub())
