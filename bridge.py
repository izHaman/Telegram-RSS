#!/usr/bin/env python3
# =============================================================================
# bridge.py — Telegram MTProto media bridge for RSS mirror pipeline
# =============================================================================

import os
import re
import json
import asyncio
from pathlib import Path

from telethon import TelegramClient
from telethon.errors import FloodWaitError
from telethon.network.connection.connection import ConnectionError


# ---------------------------------------------------------------------------
# Telegram API credentials
# ---------------------------------------------------------------------------
API_ID   = int(os.environ.get("TELEGRAM_API_ID",   0))
API_HASH =     os.environ.get("TELEGRAM_API_HASH", "")
SESSION  =     os.environ.get("TELEGRAM_SESSION",  "")

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
# Output folder + manifest
# ---------------------------------------------------------------------------
MEDIA_DIR     = Path("feeds/media")
MANIFEST_PATH = MEDIA_DIR / "manifest.json"
MEDIA_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Size gate  (50 MB — well below GitHub 100 MB hard limit)
# ---------------------------------------------------------------------------
MAX_FILE_BYTES = 50 * 1024 * 1024

# ---------------------------------------------------------------------------
# Minimum sane file size — anything smaller is almost certainly a CDN error page
# ---------------------------------------------------------------------------
MIN_FILE_BYTES = 1024   # 1 KB

# ---------------------------------------------------------------------------
# Allowed media extensions
# ---------------------------------------------------------------------------
VALID_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp", ".gif",
                    ".mp4", ".mp3", ".m4a", ".ogg"}

# ---------------------------------------------------------------------------
# Create Telegram client
# BUG FIX: use StringSession when SESSION env var is set so no .session file
# is written to the Actions runner disk, matching the old bridge.py behaviour.
# ---------------------------------------------------------------------------
def _make_client() -> TelegramClient:
    if SESSION:
        from telethon.sessions import StringSession
        return TelegramClient(
            StringSession(SESSION), API_ID, API_HASH,
            connection_retries=10, retry_delay=3, auto_reconnect=True,
        )
    # Fallback: file-based session (local dev only)
    return TelegramClient(
        "tg_bridge_session", API_ID, API_HASH,
        connection_retries=10, retry_delay=3, auto_reconnect=True,
    )


client = _make_client()

# ---------------------------------------------------------------------------
# Safe filename cleanup
# ---------------------------------------------------------------------------
def sanitize_filename(name: str) -> str:
    return re.sub(r"[^a-zA-Z0-9._-]", "_", name)


# ---------------------------------------------------------------------------
# Manifest helpers  (RESTORED — required by process_feed.py Priority 1 path)
# ---------------------------------------------------------------------------
def _load_manifest() -> dict:
    """
    Load the JSON manifest mapping "<channel>/<message_id>" → local file path.
    Returns {} on missing or corrupt file.
    """
    try:
        with open(MANIFEST_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save_manifest(manifest: dict) -> None:
    """
    Persist the in-memory manifest back to disk.
    Called once after all channels to minimise I/O and avoid partial writes.
    """
    with open(MANIFEST_PATH, "w") as f:
        json.dump(manifest, f, indent=2)


# ---------------------------------------------------------------------------
# Safe media downloader
# ---------------------------------------------------------------------------
async def safe_download(message, file_path: Path, retries: int = 3):
    """
    Download Telegram media with retry + reconnect protection.

    BUG FIX: capture the return value of download_media().
    Telethon appends the correct extension automatically when `file` is a
    directory or a Path WITHOUT extension.  When we pass a full path WITH
    extension, Telethon honours it but may still rename on MIME mismatch.
    We therefore pass a *directory* and let Telethon choose the filename,
    then rename to our canonical scheme afterwards.

    Returns the final Path on success, None on failure.
    """
    for attempt in range(1, retries + 1):
        try:
            # Download into a temp name to avoid committing partial files.
            tmp_path = file_path.with_suffix(".tmp")

            # BUG FIX: capture return value — Telethon returns the actual path used.
            actual = await message.download_media(file=str(tmp_path))

            if not actual or not os.path.exists(actual):
                raise RuntimeError("download_media returned no file")

            actual_path = Path(actual)
            size = actual_path.stat().st_size

            # BUG FIX: reject suspiciously small files (CDN error pages, HTML redirects).
            # این وضعیت قطعیه — retry فایده نداره. مستقیم None برمی‌گردیم.
            if size < MIN_FILE_BYTES:
                actual_path.unlink(missing_ok=True)
                print(f"    [skip] file too small ({size} bytes) — likely unsupported media type")
                return None

            if size > MAX_FILE_BYTES:
                actual_path.unlink(missing_ok=True)
                print(f"    [skip] {size / 1024 / 1024:.1f} MB exceeds limit")
                return None

            # Rename from Telethon's temp path to our canonical path.
            # Telethon may have used the correct extension (e.g. .mp4) even if
            # we passed .tmp — so derive canonical ext from the actual file.
            actual_ext = actual_path.suffix.lower()
            if actual_ext and actual_ext != ".tmp":
                canonical = file_path.with_suffix(actual_ext)
            else:
                canonical = file_path

            actual_path.rename(canonical)
            return canonical

        except FloodWaitError as exc:
            wait_time = int(exc.seconds) + 3
            print(f"    [wait] FloodWait {wait_time}s")
            await asyncio.sleep(wait_time)

        except (ConnectionError, asyncio.TimeoutError, OSError) as exc:
            print(f"    [retry {attempt}/{retries}] connection dropped: {exc}")
            await asyncio.sleep(attempt * 2)
            try:
                if not client.is_connected():
                    await client.connect()
            except Exception:
                pass

        except Exception as exc:
            text = str(exc).lower()
            if any(s in text for s in (
                "server closed the connection", "0 bytes read",
                "incomplete read",
            )):
                print(f"    [retry {attempt}/{retries}] {exc}")
                await asyncio.sleep(attempt * 2)
                try:
                    if not client.is_connected():
                        await client.connect()
                except Exception:
                    pass
                continue

            print(f"    [warn] download failed permanently: {exc}")
            break

    # Cleanup any partial file
    for p in (file_path, file_path.with_suffix(".tmp")):
        try:
            p.unlink(missing_ok=True)
        except Exception:
            pass

    return None


# ---------------------------------------------------------------------------
# Main sync loop
# ---------------------------------------------------------------------------
async def main():
    if not all([API_ID, API_HASH]):
        print("Bridge: Telegram credentials not set, skipping.")
        return

    manifest = _load_manifest()
    new_entries = 0

    await client.start()
    print("Bridge: authenticated via MTProto.")

    for channel in CHANNELS:
        print(f"  Syncing media from @{channel}…")

        try:
            async for message in client.iter_messages(channel, limit=25):

                if not message.media:
                    continue

                # ── De-duplication via manifest ──────────────────────────────
                # Key format MUST match process_feed.py lookup: "<channel>/<id>"
                key = f"{channel}/{message.id}"
                if key in manifest and os.path.exists(manifest[key]):
                    continue

                # ── Determine extension ───────────────────────────────────────
                ext = None
                size = 0

                if getattr(message, "file", None):
                    ext  = (message.file.ext or "").lower()
                    size = message.file.size or 0

                if not ext or ext not in VALID_EXTENSIONS:
                    continue

                # ── Size gate ─────────────────────────────────────────────────
                if size > MAX_FILE_BYTES:
                    print(
                        f"    [skip] @{channel}/{message.id} — "
                        f"{size / 1024 / 1024:.1f} MB exceeds limit"
                    )
                    continue

                # ── Build canonical filename (without extension — safe_download
                #    will add the correct one from Telethon's return value) ────
                base_name = sanitize_filename(f"tg_{channel}_{message.id}")
                file_path = MEDIA_DIR / f"{base_name}{ext}"

                print(f"    Downloading ({ext.upper()[1:]}): {file_path}")

                result = await safe_download(message, file_path)

                if result is None:
                    continue

                # BUG FIX: store the ACTUAL path returned (may differ from file_path
                # if Telethon corrected the extension).
                manifest[key] = str(result)
                new_entries += 1
                print(f"    ✓ Saved: {result}")

                await asyncio.sleep(0.4)

        except Exception as exc:
            print(f"  [warn] Failed channel @{channel}: {exc}")
            try:
                if not client.is_connected():
                    await client.connect()
            except Exception:
                pass

    await client.disconnect()

    # RESTORED: single atomic manifest write after all channels.
    # process_feed.py's Priority 1 path depends on this file existing.
    _save_manifest(manifest)
    print(f"Bridge: complete — {len(manifest)} total entries ({new_entries} new).")


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    asyncio.run(main())
