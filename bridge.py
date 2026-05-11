"""
bridge.py — Telegram MTProto Image Pre-fetcher
================================================
Runs as Step 1 of the GitHub Actions pipeline (see Fetch-feeds.sh).

WHY THIS EXISTS
---------------
RSSHub serves Telegram channel feeds over HTTP, but the image URLs it includes
point directly to Telegram's CDN (e.g. cdn4.telegram-cdn.org).  Those CDN URLs
are ephemeral — they expire within hours — and are blocked inside Iran.
This bridge authenticates to Telegram via the official MTProto protocol,
downloads the actual image binaries, commits them into the repository, and
records their paths in a manifest.  Downstream (process_feed.py) replaces the
short-lived CDN URLs with permanent raw.githubusercontent.com URLs that remain
accessible from censored networks without a VPN.

Videos are intentionally skipped here: they are too large for git storage and
can be proxied at the URL level inside process_feed.py instead.

EXECUTION FLOW
--------------
  1.  Read GitHub Actions secrets into module-level constants.
  2.  Load the existing manifest (avoids re-downloading already-cached files).
  3.  Open an authenticated MTProto session.
  4.  For each configured channel, iterate the 10 most recent messages.
  5.  Skip videos and already-cached items.
  6.  Download image → optimise as JPEG 70 % → record in manifest.
  7.  Persist the updated manifest to disk for process_feed.py to consume.
"""

import asyncio
import hashlib          # imported but unused here; kept for potential future hash-based dedup
import json
import os

from PIL import Image                         # Pillow — image re-encoding / optimisation
from telethon import TelegramClient           # MTProto client for Telegram
from telethon.sessions import StringSession   # in-memory session from a serialised string (no local .session file)

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
# All three values are injected at runtime by GitHub Actions from repository
# secrets.  Falling back to safe defaults lets the module import cleanly during
# local development or when secrets are intentionally omitted.
API_ID   = int(os.environ.get("TELEGRAM_API_ID",   0))   # numeric app ID from my.telegram.org
API_HASH =     os.environ.get("TELEGRAM_API_HASH", "")   # hex string from my.telegram.org
SESSION  =     os.environ.get("TELEGRAM_SESSION",  "")   # base64 StringSession (telethon)

# ---------------------------------------------------------------------------
# Channels to mirror via MTProto
# ---------------------------------------------------------------------------
# Only channels whose images we want committed to the repo are listed here.
# Adding a channel here does NOT add it to the RSSHub fetch rotation — for that,
# edit the CHANNELS array in Fetch-feeds.sh as well.
#
# Rationale for the subset: high-traffic channels with image-heavy posts benefit
# most from pre-fetching; text-only channels are better handled by process_feed.py's
# CDN fallback path, which avoids unnecessary MTProto round-trips.
CHANNELS = ["mamlekate", "ircfspace", "vahidonline", "iranintltv", "dw_farsi"]

# ---------------------------------------------------------------------------
# File-system paths
# ---------------------------------------------------------------------------
MEDIA_DIR     = "feeds/media"                   # directory committed into the repo
MANIFEST_PATH = f"{MEDIA_DIR}/manifest.json"    # channel/message_id → local file path


# ---------------------------------------------------------------------------
# Manifest helpers
# ---------------------------------------------------------------------------

def _load_manifest() -> dict:
    """
    Load the JSON manifest that maps Telegram message identifiers to local paths.

    The manifest is the contract between bridge.py and process_feed.py:
      key   = "<channel_slug>/<message_id>"   (e.g. "iranintltv/12345")
      value = local file path                 (e.g. "feeds/media/tg_iranintltv_12345.jpg")

    Returns an empty dict when the manifest does not yet exist or is corrupt,
    so the first run always starts fresh without crashing.
    """
    try:
        with open(MANIFEST_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _save_manifest(manifest: dict) -> None:
    """
    Persist the in-memory manifest back to disk.

    Called once after all channels have been processed — not after every
    individual download — to minimise disk I/O and avoid partial writes.
    indent=2 keeps the file human-readable in git diffs.
    """
    with open(MANIFEST_PATH, "w") as f:
        json.dump(manifest, f, indent=2)


# ---------------------------------------------------------------------------
# Image optimisation
# ---------------------------------------------------------------------------

def _optimise_jpeg(path: str) -> None:
    """
    Re-encode a downloaded media file as a progressive JPEG at 70 % quality.

    News thumbnails tolerate lossy compression well; 70 % typically cuts file
    size by 50-60 % versus Telegram's original without visible artefacts on
    phone screens.  The `optimize=True` flag enables Huffman table optimisation
    for an additional ~5 % saving at no quality cost.

    Any exception (corrupt file, unsupported format, disk full) is swallowed
    deliberately: a failed optimisation leaves the original file intact, which
    is always preferable to crashing the entire pipeline run.
    """
    try:
        with Image.open(path) as img:
            # convert("RGB") drops any alpha channel (RGBA, P-mode PNGs)
            # before saving as JPEG, which does not support transparency.
            img.convert("RGB").save(path, "JPEG", quality=70, optimize=True)
    except Exception as exc:
        print(f"    [warn] optimisation skipped for {path}: {exc}")


# ---------------------------------------------------------------------------
# Main async worker
# ---------------------------------------------------------------------------

async def _run_bridge() -> None:
    """
    Authenticate via MTProto and mirror images for all configured channels.

    Guard clause at the top: if any credential is missing the function exits
    silently.  This makes the bridge step a graceful no-op in forks or pull-
    request CI runs where secrets are intentionally not available, rather than
    causing an authentication error that marks the whole workflow as failed.
    """
    if not all([API_ID, API_HASH, SESSION]):
        # Secrets are optional — CI still works, bridge step is just a no-op.
        print("Bridge: Telegram credentials not set, skipping.")
        return

    manifest = _load_manifest()

    # StringSession reconstructs the session from a serialised string stored in
    # GitHub Secrets, so no .session file is written to the Actions runner disk.
    async with TelegramClient(StringSession(SESSION), API_ID, API_HASH) as client:
        print("Bridge: authenticated via MTProto.")

        for channel in CHANNELS:
            print(f"  Syncing images from @{channel}…")

            # limit=10 keeps the bridge fast; the RSSHub feeds also only carry
            # roughly the last 10-15 posts, so fetching more would be wasteful.
            async for message in client.iter_messages(channel, limit=10):

                # Messages with no attached media (text-only posts) are skipped;
                # process_feed.py will inject a placeholder thumbnail for those.
                if not message.media:
                    continue

                # ── Video guard ──────────────────────────────────────────────
                # Video documents (mp4, mkv …) can be hundreds of megabytes.
                # Storing them in git would balloon the repository and burn
                # GitHub Actions minutes needlessly.  Instead, process_feed.py
                # keeps the original telesco.pe / CDN URL and wraps it in
                # <enclosure> + <media:content> tags so Feeder streams it.
                is_video = (
                    hasattr(message.media, "document")
                    and "video" in (message.media.document.mime_type or "")
                )
                if is_video:
                    continue

                # ── De-duplication via manifest ──────────────────────────────
                # The manifest key format MUST match the lookup key used in
                # process_feed.py (_process_item) so the two files stay in sync.
                key = f"{channel}/{message.id}"
                if key in manifest and os.path.exists(manifest[key]):
                    continue  # already cached from a previous run — skip download

                # ── Download ─────────────────────────────────────────────────
                # Naming scheme: tg_<channel>_<message_id>.jpg
                # process_feed.py relies on os.path.basename() of this path,
                # so changing the pattern here requires a matching change there.
                file_path = f"{MEDIA_DIR}/tg_{channel}_{message.id}.jpg"
                print(f"    Downloading: {file_path}")

                try:
                    # Telethon handles partial downloads and retries internally.
                    await message.download_media(file=file_path)
                except Exception as exc:
                    print(f"    [warn] download failed: {exc}")
                    continue  # non-fatal — move on to the next message

                # Re-encode for storage efficiency before recording in manifest
                _optimise_jpeg(file_path)
                manifest[key] = file_path

        # Persist once after all channels — a single atomic write is safer than
        # writing after each download and avoids manifest corruption on crash.
        _save_manifest(manifest)
        print(f"Bridge: complete — {len(manifest)} entries in manifest.")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    os.makedirs(MEDIA_DIR, exist_ok=True)   # create feeds/media/ if this is a fresh clone
    asyncio.run(_run_bridge())
