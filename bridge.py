import asyncio
import hashlib
import json
import os

from PIL import Image
from telethon import TelegramClient
from telethon.sessions import StringSession

# ─── Credentials (injected from GitHub Actions secrets) ───────────────────────
API_ID   = int(os.environ.get("TELEGRAM_API_ID",   0))
API_HASH =     os.environ.get("TELEGRAM_API_HASH", "")
SESSION  =     os.environ.get("TELEGRAM_SESSION",  "")

# Channels to pre-fetch via MTProto.
# Videos are intentionally excluded — they are served from the original CDN URL
# inside <enclosure>/<media:content> tags, so there is no need to store them
# in the repository.  Keeping only images here prevents repo/storage bloat and
# avoids wasting GitHub Actions free minutes on large binary downloads.
CHANNELS = ["mamlekate", "ircfspace", "vahidonline", "iranintltv", "dw_farsi"]

MEDIA_DIR     = "feeds/media"
MANIFEST_PATH = f"{MEDIA_DIR}/manifest.json"


def _load_manifest() -> dict:
    """Load the existing manifest so we never re-download a known file."""
    try:
        with open(MANIFEST_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save_manifest(manifest: dict) -> None:
    with open(MANIFEST_PATH, "w") as f:
        json.dump(manifest, f, indent=2)


def _optimise_jpeg(path: str) -> None:
    """
    Re-encode an image as JPEG at 70 % quality.
    Reduces file size by ~50-60 % with imperceptible quality loss for news thumbnails.
    Silently skips files that Pillow cannot open (e.g. corrupt downloads).
    """
    try:
        with Image.open(path) as img:
            img.convert("RGB").save(path, "JPEG", quality=70, optimize=True)
    except Exception as exc:
        print(f"    [warn] optimisation skipped for {path}: {exc}")


async def _run_bridge() -> None:
    if not all([API_ID, API_HASH, SESSION]):
        # Secrets are optional — CI still works, bridge step is just a no-op.
        print("Bridge: Telegram credentials not set, skipping.")
        return

    manifest = _load_manifest()

    async with TelegramClient(StringSession(SESSION), API_ID, API_HASH) as client:
        print("Bridge: authenticated via MTProto.")

        for channel in CHANNELS:
            print(f"  Syncing images from @{channel}…")

            async for message in client.iter_messages(channel, limit=10):
                if not message.media:
                    continue

                # Skip video documents — they will be served from their original
                # telesco.pe / CDN URL and do not belong in the repository.
                is_video = (
                    hasattr(message.media, "document")
                    and "video" in (message.media.document.mime_type or "")
                )
                if is_video:
                    continue

                # Manifest key matches what process_feed.py uses for lookup:
                # "channel/message_id"  →  local file path
                key = f"{channel}/{message.id}"
                if key in manifest and os.path.exists(manifest[key]):
                    continue  # already cached from a previous run

                # Naming convention understood by process_feed.py's manifest lookup
                file_path = f"{MEDIA_DIR}/tg_{channel}_{message.id}.jpg"
                print(f"    Downloading: {file_path}")

                try:
                    await message.download_media(file=file_path)
                except Exception as exc:
                    print(f"    [warn] download failed: {exc}")
                    continue

                _optimise_jpeg(file_path)
                manifest[key] = file_path

        _save_manifest(manifest)
        print(f"Bridge: complete — {len(manifest)} entries in manifest.")


if __name__ == "__main__":
    os.makedirs(MEDIA_DIR, exist_ok=True)
    asyncio.run(_run_bridge())
