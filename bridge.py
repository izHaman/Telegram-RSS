import os
import asyncio
from telethon import TelegramClient
from telethon.sessions import StringSession

# Media Bridge
# Fetches high-quality media directly from Telegram channels using MTProto

# Environment configuration fetched from GitHub Secrets
API_ID = int(os.environ.get("TELEGRAM_API_ID"))
API_HASH = os.environ.get("TELEGRAM_API_HASH")
SESSION = os.environ.get("TELEGRAM_SESSION")

# Target channels to scan for media
CHANNELS = ["mamlekate", "vahidonline", "iranintltv", "dw_farsi"]

async def download_recent_media():
    async with TelegramClient(StringSession(SESSION), API_ID, API_HASH) as client:
        print("Connected to Telegram Bridge...")
        
        for channel in CHANNELS:
            print(f"Scanning channel: @{channel}")
            # Fetching last 5 messages to ensure sync
            async for message in client.iter_messages(channel, limit=5):
                if message.media:
                    # Generate a unique hash for the media file
                    file_name = f"{message.id}_{channel}"
                    path = f"feeds/media/{file_name}"
                    
                    if not os.path.exists(path):
                        print(f"Downloading media from message {message.id}...")
                        await message.download_media(file=path)

if __name__ == "__main__":
    if not os.path.exists("feeds/media"):
        os.makedirs("feeds/media")
    asyncio.run(download_recent_media())
