#!/usr/bin/env python3
# =============================================================================
# bridge.py — Telegram MTProto media bridge for RSS mirror pipeline
# =============================================================================

import os
import re
import asyncio
from pathlib import Path

from telethon import TelegramClient
from telethon.errors import FloodWaitError
from telethon.network.connection.connection import ConnectionError


# ---------------------------------------------------------------------------
# Telegram API credentials
# ---------------------------------------------------------------------------
API_ID = int(os.environ["TG_API_ID"])
API_HASH = os.environ["TG_API_HASH"]

# ---------------------------------------------------------------------------
# Channels to mirror media from
# ---------------------------------------------------------------------------
CHANNELS = [
    "mamlekate",
    "ircfspace",
    "vahidonline",
    "iranintltv",
    "drtel",
    "hatricktv",
    "raptv",
    "jadivarlog",
    "digitechirchannel",
    "STCdownload",
    "khateraaat",
    "dw_farsi",
]

# ---------------------------------------------------------------------------
# Output folder
# ---------------------------------------------------------------------------
MEDIA_DIR = Path("feeds/media")
MEDIA_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Allowed media extensions
# ---------------------------------------------------------------------------
VALID_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".gif",
    ".mp4",
    ".mp3",
    ".m4a",
    ".ogg",
}

# ---------------------------------------------------------------------------
# Create Telegram client
# ---------------------------------------------------------------------------
client = TelegramClient(
    "tg_bridge_session",
    API_ID,
    API_HASH,
    connection_retries=10,
    retry_delay=3,
    auto_reconnect=True,
)

# ---------------------------------------------------------------------------
# Safe filename cleanup
# ---------------------------------------------------------------------------
def sanitize_filename(name: str) -> str:
    return re.sub(r"[^a-zA-Z0-9._-]", "_", name)


# ---------------------------------------------------------------------------
# Safe media downloader
# ---------------------------------------------------------------------------
async def safe_download(message, file_path: str, retries: int = 3) -> bool:
    """
    Download Telegram media with retry + reconnect protection.
    Prevents transient MTProto disconnects from killing the pipeline.
    """

    for attempt in range(1, retries + 1):

        try:
            await message.download_media(file=file_path)

            # Validate non-empty file
            if not os.path.exists(file_path):
                raise RuntimeError("download produced no file")

            if os.path.getsize(file_path) == 0:
                raise RuntimeError("downloaded empty file")

            return True

        except FloodWaitError as exc:

            wait_time = int(exc.seconds) + 3

            print(f"    [wait] FloodWait {wait_time}s")

            await asyncio.sleep(wait_time)

        except (ConnectionError, asyncio.TimeoutError, OSError) as exc:

            print(
                f"    [retry {attempt}/{retries}] "
                f"connection dropped: {exc}"
            )

            await asyncio.sleep(attempt * 2)

            try:
                if not client.is_connected():
                    await client.connect()
            except Exception:
                pass

        except Exception as exc:

            text = str(exc).lower()

            if (
                "server closed the connection" in text
                or "0 bytes read" in text
                or "incomplete read" in text
            ):

                print(
                    f"    [retry {attempt}/{retries}] "
                    f"telegram connection interrupted"
                )

                await asyncio.sleep(attempt * 2)

                try:
                    if not client.is_connected():
                        await client.connect()
                except Exception:
                    pass

                continue

            print(f"    [warn] download failed permanently: {exc}")

            break

    # cleanup corrupt partial file
    try:
        if os.path.exists(file_path):
            os.remove(file_path)
    except Exception:
        pass

    return False


# ---------------------------------------------------------------------------
# Main sync loop
# ---------------------------------------------------------------------------
async def main():

    await client.start()

    print("Bridge: authenticated via MTProto.")

    for channel in CHANNELS:

        print(f"  Syncing media from @{channel}…")

        try:
            async for message in client.iter_messages(channel, limit=25):

                if not message.media:
                    continue

                # -------------------------------------------------------------------
                # Determine extension
                # -------------------------------------------------------------------
                ext = None

                if getattr(message, "file", None):
                    ext = message.file.ext

                if not ext:
                    continue

                ext = ext.lower()

                if ext not in VALID_EXTENSIONS:
                    continue

                # -------------------------------------------------------------------
                # Build local filename
                # -------------------------------------------------------------------
                filename = sanitize_filename(
                    f"tg_{channel}_{message.id}{ext}"
                )

                file_path = MEDIA_DIR / filename

                # Skip already-downloaded files
                if file_path.exists():
                    continue

                print(f"    Downloading ({ext.upper()[1:]}): {file_path}")

                success = await safe_download(message, str(file_path))

                if not success:
                    continue

                print(f"    ✓ Saved: {file_path}")

                # -------------------------------------------------------------------
                # Small delay to reduce MTProto stress
                # -------------------------------------------------------------------
                await asyncio.sleep(0.4)

        except Exception as exc:

            print(f"  [warn] Failed channel @{channel}: {exc}")

            try:
                if not client.is_connected():
                    await client.connect()
            except Exception:
                pass

            continue

    await client.disconnect()


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    asyncio.run(main())
