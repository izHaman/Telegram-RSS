"""
bridge.py — Telegram MTProto Media Pre-fetcher
================================================
Runs as Step 1 of the GitHub Actions pipeline (see Fetch-feeds.sh).

WHY THIS EXISTS
---------------
RSSHub serves Telegram channel feeds over HTTP, but the media URLs it includes
point directly to Telegram's CDN (e.g. cdn4.telegram-cdn.org).  Those CDN URLs
are ephemeral — they expire within hours — and are blocked inside Iran.
This bridge authenticates to Telegram via the official MTProto protocol,
downloads ALL media types (images, videos, audio, GIFs), commits them into the
repository, and records their paths in a manifest.  Downstream (process_feed.py)
replaces the short-lived CDN URLs with permanent raw.githubusercontent.com URLs
that remain accessible from censored networks without a VPN.

SIZE POLICY
-----------
To keep the repository from ballooning, we enforce a per-file size limit
(MAX_FILE_BYTES).  Files exceeding this limit are skipped — their original CDN
URL will survive in the XML as a last resort.  For most news channels the
average video is under 20 MB, so the 50 MB ceiling covers the vast majority
of posts while keeping git history manageable.

EXECUTION FLOW
--------------
  1.  Read GitHub Actions secrets into module-level constants.
  2.  Load the existing manifest (avoids re-downloading already-cached files).
  3.  Open an authenticated MTProto session.
  4.  For each configured channel, iterate the 10 most recent messages.
  5.  Skip already-cached items and oversized files.
  6.  Download media → optimise images → record in manifest.
  7.  Persist the updated manifest to disk for process_feed.py to consume.
"""

import asyncio
import hashlib          # reserved for future hash-based dedup utilities
import json
import mimetypes
import os

from PIL import Image                         # Pillow — image re-encoding / optimisation
from telethon import TelegramClient           # MTProto client for Telegram
from telethon.sessions import StringSession   # in-memory session from a serialised string

# ---------------------------------------------------------------------------
# Credentials  (injected at runtime by GitHub Actions secrets)
# ---------------------------------------------------------------------------
API_ID   = int(os.environ.get("TELEGRAM_API_ID",   0))
API_HASH =     os.environ.get("TELEGRAM_API_HASH", "")
SESSION  =     os.environ.get("TELEGRAM_SESSION",  "")

# ---------------------------------------------------------------------------
# Size gate
# ---------------------------------------------------------------------------
# Files larger than this threshold are skipped at download time.
# 50 MB is a pragmatic ceiling:
#   • Well below GitHub's 100 MB single-file hard limit.
#   • Covers the vast majority of Telegram news videos (1–15 MB typical).
#   • Prevents long-form video dumps from bloating the repository history.
# Raise this value if your channels post larger files and you have Git LFS
# configured; lower it to be more conservative with GitHub Actions storage.
MAX_FILE_BYTES = 50 * 1024 * 1024   # 50 MB

# ---------------------------------------------------------------------------
# Channels to mirror via MTProto
# ---------------------------------------------------------------------------
# Keep this list in sync with CHANNELS in Fetch-feeds.sh.
# Only channels whose media we want committed to the repo are listed here.
CHANNELS = ["mamlekate", "ircfspace", "vahidonline", "iranintltv", "dw_farsi", "drtel", "khateraaat", "raptv", "whynationsfail2019", "jadivarlog", "digitechirchannel", "hatricktv"]

# ---------------------------------------------------------------------------
# File-system paths
# ---------------------------------------------------------------------------
MEDIA_DIR     = "feeds/media"
MANIFEST_PATH = f"{MEDIA_DIR}/manifest.json"

# ---------------------------------------------------------------------------
# MIME → extension map
# ---------------------------------------------------------------------------
# We derive file extensions from MIME types reported by Telegram so the saved
# filename always reflects the true format — critical for process_feed.py's
# URL-rewriting and for media players that rely on file extensions.
_MIME_TO_EXT = {
    "video/mp4":          "mp4",
    "video/x-matroska":   "mkv",
    "video/quicktime":    "mov",
    "video/webm":         "webm",
    "audio/mpeg":         "mp3",
    "audio/ogg":          "ogg",
    "audio/mp4":          "m4a",
    "image/jpeg":         "jpg",
    "image/png":          "png",
    "image/gif":          "gif",
    "image/webp":         "webp",
}


def _ext_for_mime(mime: str) -> str:
    """
    Return a lowercase file extension for a given MIME type string.
    Falls back to stdlib mimetypes, then to 'bin' for fully unknown types.
    """
    ext = _MIME_TO_EXT.get(mime)
    if ext:
        return ext
    # stdlib fallback: 'image/gif' → '.gif' → 'gif'
    guessed = mimetypes.guess_extension(mime) or ".bin"
    return guessed.lstrip(".")


# ---------------------------------------------------------------------------
# Manifest helpers
# ---------------------------------------------------------------------------

def _load_manifest() -> dict:
    """
    Load the JSON manifest mapping Telegram message IDs to local file paths.

    Key format  : "<channel_slug>/<message_id>"  (e.g. "iranintltv/12345")
    Value format: local file path                (e.g. "feeds/media/tg_iranintltv_12345.mp4")

    Returns {} when missing or corrupt — first run starts fresh without crashing.
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
    indent=2 keeps the file human-readable in git diffs.
    """
    with open(MANIFEST_PATH, "w") as f:
        json.dump(manifest, f, indent=2)


# ---------------------------------------------------------------------------
# Image optimisation
# ---------------------------------------------------------------------------

def _optimise_jpeg(path: str) -> None:
    """
    Re-encode a downloaded image as JPEG at 70 % quality to reduce repo size.

    News thumbnails tolerate lossy compression well; 70 % typically cuts file
    size by 50-60 % with no visible artefact on phone screens.

    GIFs and videos are NOT passed to this function — only static images.
    Errors are swallowed so a bad optimisation never crashes the whole pipeline.
    """
    try:
        with Image.open(path) as img:
            # convert("RGB") drops the alpha channel before saving as JPEG,
            # which does not support transparency.
            img.convert("RGB").save(path, "JPEG", quality=70, optimize=True)
    except Exception as exc:
        print(f"    [warn] image optimisation skipped for {path}: {exc}")


# ---------------------------------------------------------------------------
# Main async worker
# ---------------------------------------------------------------------------

async def _run_bridge() -> None:
    """
    Authenticate via MTProto and mirror all supported media types for all
    configured channels.

    Guard clause: exits silently when any credential is missing, making the
    bridge step a graceful no-op in forks / PR CI without secrets.
    """
    if not all([API_ID, API_HASH, SESSION]):
        # Missing secrets are expected in fork environments — not an error.
        print("Bridge: Telegram credentials not set, skipping.")
        return

    manifest = _load_manifest()

    # StringSession reconstructs the client from a serialised string stored in
    # GitHub Secrets — no .session file is written to the Actions runner disk.
    async with TelegramClient(StringSession(SESSION), API_ID, API_HASH) as client:
        print("Bridge: authenticated via MTProto.")

        for channel in CHANNELS:
            print(f"  Syncing media from @{channel}…")

            # limit=10 matches the RSSHub feed window (≈ last 10 posts).
            async for message in client.iter_messages(channel, limit=10):

                # Skip text-only messages that carry no media attachment.
                if not message.media:
                    continue

                # ── De-duplication via manifest ──────────────────────────────
                # The key format MUST match the lookup key used in
                # process_feed.py._process_item so both files stay in sync.
                key = f"{channel}/{message.id}"
                if key in manifest and os.path.exists(manifest[key]):
                    continue   # already committed in a previous run — skip

                # ── Determine MIME type, extension, and file size ─────────────
                # Telegram exposes two media shapes:
                #   • Photo   → Telethon Photo object (always JPEG when saved)
                #   • Document → carries explicit mime_type and size attributes
                #                (covers video, audio, GIF, sticker, file …)
                mime = None
                size = 0

                if hasattr(message.media, "document"):
                    doc  = message.media.document
                    mime = doc.mime_type or ""
                    size = doc.size or 0        # bytes, reported by Telegram
                elif hasattr(message.media, "photo"):
                    mime = "image/jpeg"
                    # Photo object does not expose a pre-download byte count;
                    # photos are small enough that skipping the size gate is safe.
                    size = 0

                if not mime:
                    continue   # unrecognised media shape — skip safely

                ext = _ext_for_mime(mime)

                # ── Size gate ────────────────────────────────────────────────
                # Enforce MAX_FILE_BYTES for documents.
                # Photos bypass the check (they are always small JPEG thumbnails).
                if size > MAX_FILE_BYTES:
                    print(
                        f"    [skip] @{channel}/{message.id} — "
                        f"{size / 1024 / 1024:.1f} MB exceeds "
                        f"{MAX_FILE_BYTES // 1024 // 1024} MB limit"
                    )
                    continue

                # ── Download ─────────────────────────────────────────────────
                # Naming scheme: tg_<channel>_<message_id>.<ext>
                # process_feed.py calls os.path.basename() on this value, so the
                # scheme must stay identical between the two files.
                file_path = f"{MEDIA_DIR}/tg_{channel}_{message.id}.{ext}"
                print(f"    Downloading ({ext.upper()}): {file_path}")

                try:
                    # Telethon handles chunked download and retries internally.
                    await message.download_media(file=file_path)
                except Exception as exc:
                    print(f"    [warn] download failed: {exc}")
                    continue   # non-fatal — move to next message

                # ── Post-processing ──────────────────────────────────────────
                # Optimise static images to save repository space.
                # GIFs are animation sequences — JPEG re-encoding would destroy them.
                # Videos and audio are stored verbatim (no lossless recompression here).
                if mime.startswith("image/") and ext != "gif":
                    _optimise_jpeg(file_path)

                manifest[key] = file_path
                print(f"    ✓ Saved: {file_path}")

        # Single atomic write after all channels — safer than writing per-download.
        _save_manifest(manifest)
        print(f"Bridge: complete — {len(manifest)} entries in manifest.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    os.makedirs(MEDIA_DIR, exist_ok=True)   # create feeds/media/ on a fresh clone
    asyncio.run(_run_bridge())
