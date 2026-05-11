#!/usr/bin/env python3
"""
process_feed.py — Per-item RSS feed processor for Telegram channels.

Replaces the bash media-download loop and processor.pl entirely.
Runs once per channel slug, reads XML from stdin, writes to stdout.

Image strategy  : bridge manifest → cached file → CDN fallback → GitHub raw URL
Video/Audio strategy: keep original CDN URL as-is (no repo storage, no wasted
                      Actions minutes) and expose it through proper RSS tags so
                      Feeder Android can stream it directly.

Usage:
    python3 process_feed.py <slug> <raw_base_url> <placeholder_url> < in.xml > out.xml
"""

import hashlib
import json
import os
import re
import sys
import urllib.request

# ─── Media type classification ────────────────────────────────────────────────
VIDEO_EXTS = {"mp4", "mkv", "mov"}
AUDIO_EXTS = {"mp3", "ogg", "m4a"}
IMAGE_EXTS = {"jpg", "jpeg", "png", "gif", "webp"}

MIME = {
    "mp4":  "video/mp4",          "mkv": "video/x-matroska",
    "mov":  "video/quicktime",    "mp3": "audio/mpeg",
    "ogg":  "audio/ogg",          "m4a": "audio/mp4",
    "jpg":  "image/jpeg",         "jpeg": "image/jpeg",
    "png":  "image/png",          "gif":  "image/gif",
    "webp": "image/webp",
}

MEDIA_DIR     = "feeds/media"
MANIFEST_PATH = f"{MEDIA_DIR}/manifest.json"

# Shared HTTP headers for CDN image downloads
_DL_HEADERS = {"User-Agent": "Mozilla/5.0", "Referer": "https://t.me/"}

# Matches CDN image/video URLs and bare telesco.pe file links
_URL_RE = re.compile(
    r"https://[^\s\"<]+"
    r"(?:\.(?:mp4|mkv|mov|mp3|m4a|jpg|jpeg|png|gif|webp))"
    r"|https://[^\s\"<]*telesco\.pe/file/[^\"<\s?]*",
    re.IGNORECASE,
)


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _load_manifest() -> dict:
    """Return the bridge pre-download manifest, or an empty dict if missing."""
    try:
        with open(MANIFEST_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def _cdn_hash(url: str) -> str:
    """
    Stable MD5 of a normalised URL.
    Strips query strings and unescapes &amp; — must mirror the old Bash logic
    so previously-cached files are still found on repeat runs.
    """
    clean = url.split("?")[0].replace("&amp;", "&")
    return hashlib.md5(clean.encode()).hexdigest()


def _find_cached(h: str):
    """
    Scan MEDIA_DIR for a file whose stem equals h (any extension, no .tmp).
    Returns (path, ext) or (None, None).
    """
    for name in os.listdir(MEDIA_DIR):
        stem, _, ext = name.rpartition(".")
        if stem == h and not name.endswith(".tmp"):
            return f"{MEDIA_DIR}/{name}", ext.lower()
    return None, None


def _fetch_image(url: str, h: str):
    """
    Download one image from url and save as feeds/media/<h>.jpg.
    Returns (path, 'jpg') on success, (None, None) on any failure.
    Rejects HTML error pages that CDNs sometimes return instead of 404.
    """
    try:
        req = urllib.request.Request(url, headers=_DL_HEADERS)
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()
        # Treat suspiciously small responses or HTML pages as failures
        if len(data) < 512 or b"<html" in data[:256].lower():
            return None, None
        path = f"{MEDIA_DIR}/{h}.jpg"
        with open(path, "wb") as fh:
            fh.write(data)
        return path, "jpg"
    except Exception as exc:
        print(f"  [warn] image download failed {url}: {exc}", file=sys.stderr)
        return None, None


def _enclosure(url: str, ext: str) -> str:
    # RSS 2.0 standard attachment tag — Feeder uses this for audio/podcast
    length = "5000000" if ext in VIDEO_EXTS else "102400"
    mime   = MIME.get(ext, "application/octet-stream")
    return f'<enclosure url="{url}" type="{mime}" length="{length}" />'


def _media_content(url: str, ext: str) -> str:
    # Media RSS tag — Feeder uses <media:content> for inline video playback
    medium = ("video" if ext in VIDEO_EXTS
              else "audio" if ext in AUDIO_EXTS
              else "image")
    mime = MIME.get(ext, "application/octet-stream")
    return f'<media:content url="{url}" type="{mime}" medium="{medium}" />'


# ─── Core per-item logic ──────────────────────────────────────────────────────

def _process_item(body: str, slug: str, raw_base: str,
                  placeholder: str, manifest: dict) -> str:
    """
    Transform the inner body of one <item> block.
    Called by re.sub; the <item> wrapper tags are re-added by the caller.

    Images  → localised to GitHub raw URL (bridge cache preferred).
    Video/Audio → original CDN URL preserved; exposed via enclosure +
                  media:content so Feeder can stream without storing the
                  file in the repository.
    """
    # Remove stale enclosure/media tags so we can rebuild them cleanly
    body = re.sub(r"<enclosure[^>]*/>\s*",     "", body, flags=re.IGNORECASE)
    body = re.sub(r"<media:content[^>]*/>\s*", "", body, flags=re.IGNORECASE)

    # Extract channel + message ID from the canonical t.me item link
    link_m   = re.search(r"https://t\.me/([^/\"<\s]+)/(\d+)", body)
    msg_chan = link_m.group(1) if link_m else slug
    msg_id   = link_m.group(2) if link_m else None

    best_url = None   # URL that will populate enclosure / media:content
    best_ext = None

    seen = set()
    for raw_url in _URL_RE.findall(body):
        if raw_url in seen:
            continue
        seen.add(raw_url)

        clean = raw_url.split("?")[0].replace("&amp;", "&")

        # Infer extension — telesco.pe bare links are always video
        ext_m = re.search(r"\.([a-z0-9]{2,4})$", clean, re.IGNORECASE)
        ext   = ext_m.group(1).lower() if ext_m else (
                "mp4" if "telesco.pe" in clean else None)

        if not ext:
            continue

        # ── Video / Audio ────────────────────────────────────────────────────
        # Never download to the repo — raw.githubusercontent.com doesn't send
        # Accept-Ranges headers reliably and file storage balloons quickly.
        # Instead keep the original CDN URL and surface it via media tags so
        # Feeder can open/stream it natively.
        if ext in VIDEO_EXTS | AUDIO_EXTS:
            best_url, best_ext = raw_url, ext
            # Inject a direct tap-to-open link in the description as a fallback
            # for readers that don't render media:content inline.
            body = re.sub(
                r"(<description>\s*<!\[CDATA\[)",
                rf'\1<p><a href="{raw_url}">▶ Play {ext.upper()}</a></p>',
                body,
            )
            continue  # leave the original URL in the XML body untouched

        # ── Images ───────────────────────────────────────────────────────────
        if ext in IMAGE_EXTS:
            # Priority 1: bridge pre-downloaded this message's image via MTProto
            manifest_key = f"{msg_chan}/{msg_id}"
            if msg_id and manifest_key in manifest:
                local = manifest[manifest_key]
                if os.path.exists(local):
                    fname  = os.path.basename(local)
                    gh_url = f"{raw_base}/{MEDIA_DIR}/{fname}"
                    body   = body.replace(raw_url, gh_url)
                    best_url, best_ext = gh_url, local.rsplit(".", 1)[-1]
                    continue

            # Priority 2: already downloaded and committed in a previous run
            h = _cdn_hash(raw_url)
            cached, c_ext = _find_cached(h)
            if cached:
                gh_url = f"{raw_base}/{MEDIA_DIR}/{os.path.basename(cached)}"
                body   = body.replace(raw_url, gh_url)
                best_url, best_ext = gh_url, c_ext
                continue

            # Priority 3: download from CDN now
            # Using Python str.replace() here (not sed) avoids breakage when
            # the URL contains shell-special characters like &, ?, or %.
            path, d_ext = _fetch_image(raw_url, h)
            if path:
                gh_url = f"{raw_base}/{MEDIA_DIR}/{os.path.basename(path)}"
                body   = body.replace(raw_url, gh_url)
                best_url, best_ext = gh_url, d_ext

    # ── Build enclosure + media:content ──────────────────────────────────────
    if best_url and best_ext:
        suffix = f"{_enclosure(best_url, best_ext)}\n{_media_content(best_url, best_ext)}"
    else:
        # Text-only post: use placeholder so Feeder shows something visual
        suffix = (
            f"{_enclosure(placeholder, 'jpg')}\n"
            f"{_media_content(placeholder, 'jpg')}"
        )
        body = re.sub(
            r"(<description>\s*<!\[CDATA\[)",
            rf'\1<img src="{placeholder}" style="width:100%;border-radius:8px;'
            rf'margin-bottom:10px" /><br/>',
            body,
        )

    return body.rstrip() + "\n" + suffix + "\n"


# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) != 4:
        sys.exit("Usage: process_feed.py <slug> <raw_base_url> <placeholder_url>")

    slug, raw_base, placeholder = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(MEDIA_DIR, exist_ok=True)

    xml = sys.stdin.read()
    if not xml:
        return

    manifest = _load_manifest()

    # Declare the Media RSS namespace on the root element if not already present.
    # Feeder requires this namespace for <media:content> to be parsed correctly.
    if "xmlns:media=" not in xml:
        xml = re.sub(
            r"<rss\b",
            '<rss xmlns:media="http://search.yahoo.com/mrss/"',
            xml, count=1,
        )

    # Process every <item> block independently so we can match each one against
    # its specific t.me message ID and the bridge manifest.
    xml = re.sub(
        r"<item>(.*?)</item>",
        lambda m: "<item>" + _process_item(
            m.group(1), slug, raw_base, placeholder, manifest
        ) + "</item>",
        xml,
        flags=re.DOTALL,
    )

    sys.stdout.write(xml)


if __name__ == "__main__":
    main()
