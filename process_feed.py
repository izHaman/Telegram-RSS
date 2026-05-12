#!/usr/bin/env python3
"""
process_feed.py — Per-channel RSS feed processor for Telegram channels
=======================================================================
Reads raw RSSHub XML from stdin, rewrites all media URLs so they are
accessible from censored networks (Iran), and writes the enriched XML to stdout.

WHY THIS FILE EXISTS
--------------------
RSSHub converts Telegram channel posts to RSS 2.0 XML, but the media URLs it
embeds point to Telegram's CDN — ephemeral, expiring, and blocked in Iran.

This processor replaces every blocked URL with a permanent raw.githubusercontent.com
URL by following the same three-tier strategy for ALL media types (images,
videos, audio, GIFs):

  Priority 1 — Bridge manifest  : bridge.py pre-downloaded the file via MTProto
               and recorded its local path.  Fastest path, no CDN hit.

  Priority 2 — Local cache      : the file was downloaded and committed in a
               previous run.  Found by an MD5-hash scan of feeds/media/.

  Priority 3 — CDN download     : download the file from the CDN now, save it
               to feeds/media/, and reference it via a GitHub raw URL.
               For large files (> MAX_DOWNLOAD_BYTES) the CDN URL is kept
               as-is — the user may not be able to load it in Iran, but the
               post content is preserved.

VIDEO / AUDIO / GIF POSTS
--------------------------
A styled bilingual banner is injected into <description> for every non-image
media post.  The banner is a pure-CSS HTML block that renders in any WebView-
based RSS reader and gives the user a clearly visible, tappable "Open Media |
پخش رسانه" link pointing to the GitHub raw URL of the committed file.

USAGE
-----
    python3 process_feed.py <slug> <raw_base_url> <placeholder_url> < in.xml > out.xml

    slug          — Telegram channel username (e.g. "iranintltv")
    raw_base_url  — https://raw.githubusercontent.com/<owner>/<repo>/main
    placeholder_url — GitHub raw URL to the default thumbnail JPEG

PIPELINE POSITION
-----------------
    bridge.py  →  [this file]  →  feeds/<slug>.xml  →  git commit & push
"""

import hashlib
import json
import os
import re
import sys
import urllib.request

# ---------------------------------------------------------------------------
# Media-type classification tables
# ---------------------------------------------------------------------------
VIDEO_EXTS = {"mp4", "mkv", "mov", "webm"}
AUDIO_EXTS = {"mp3", "ogg", "m4a"}
IMAGE_EXTS = {"jpg", "jpeg", "png", "gif", "webp"}

# All downloadable extensions: used to decide whether to attempt local storage.
# GIF is classified as image-extension here so it follows the image download path
# (CDN download → git commit → GitHub raw URL), which is exactly what we want.
ALL_MEDIA_EXTS = VIDEO_EXTS | AUDIO_EXTS | IMAGE_EXTS

# MIME type map used for <enclosure type="…"> and <media:content type="…">
MIME = {
    "mp4":  "video/mp4",          "mkv": "video/x-matroska",
    "mov":  "video/quicktime",    "webm": "video/webm",
    "mp3":  "audio/mpeg",         "ogg": "audio/ogg",
    "m4a":  "audio/mp4",          "jpg": "image/jpeg",
    "jpeg": "image/jpeg",         "png": "image/png",
    "gif":  "image/gif",          "webp": "image/webp",
}

# ---------------------------------------------------------------------------
# File-system paths  (must stay in sync with bridge.py)
# ---------------------------------------------------------------------------
MEDIA_DIR     = "feeds/media"
MANIFEST_PATH = f"{MEDIA_DIR}/manifest.json"

# ---------------------------------------------------------------------------
# Download size limit for CDN fallback
# ---------------------------------------------------------------------------
# When bridge.py has NOT pre-downloaded a file and there is no local cache,
# we attempt a live CDN download.  Files exceeding this limit are skipped to
# prevent GitHub Actions from running out of disk space or timing out.
# bridge.py enforces a separate (higher) limit for MTProto downloads.
MAX_DOWNLOAD_BYTES = 50 * 1024 * 1024   # 50 MB

# ---------------------------------------------------------------------------
# HTTP headers for CDN downloads
# ---------------------------------------------------------------------------
# Telegram's CDN returns 403 for bare Python urllib requests, so we spoof a
# browser User-Agent and add the Referer that the Telegram web client sends.
_DL_HEADERS = {"User-Agent": "Mozilla/5.0", "Referer": "https://t.me/"}

# ---------------------------------------------------------------------------
# URL regex
# ---------------------------------------------------------------------------
# Matches three categories of media URL found inside RSSHub Telegram feeds:
#   A) Direct file URLs ending with a known media extension
#   B) Bare telesco.pe video links (no extension in path, always video)
#   C) Unsplash URLs injected by RSSHub as placeholder images for text-only
#      posts — detected here so they can be stripped in the processing loop.
_URL_RE = re.compile(
    r"https://[^\s\"<]+"
    r"(?:\.(?:mp4|mkv|mov|webm|mp3|m4a|ogg|jpg|jpeg|png|gif|webp))"
    r"|https://[^\s\"<]*telesco\.pe/file/[^\"<\s?]*"
    r"|https://(?:source|images)\.unsplash\.com[^\s\"<]*",
    re.IGNORECASE,
)

# Matches <img> tags containing an Unsplash URL — used to strip them cleanly.
_UNSPLASH_IMG_RE = re.compile(
    r"<img[^>]*src=[\"'][^\"']*unsplash\.com[^\"']*[\"'][^>]*/?>",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Bilingual media banner
# ---------------------------------------------------------------------------
# Injected into <description> CDATA for every video, audio, or GIF post.
# Renders in any WebView-based RSS reader (Feeder, Reeder, NetNewsWire …).
#
# Design notes:
#   • Pure inline CSS — no external stylesheet, no JavaScript, no network
#     requests from the banner itself.
#   • Dark gradient background — clearly visible on both light and dark themes.
#   • Accent colour #e94560 — distinctive, not confused with error/alert red.
#   • Full block is tappable (display:block on <a>) — no tiny hit target.
#   • Bilingual: English first for universal recognition, Persian below it
#     for Iranian readers who may not recognise English immediately.
#   • {url} and {ext_label} are replaced at call time by _make_media_banner().
_MEDIA_BANNER_TEMPLATE = """\
<a href="{url}" style="display:block;text-decoration:none;margin:10px 0;\
background:linear-gradient(135deg,#1a1a2e,#16213e);border-radius:12px;\
padding:14px 16px;border-left:4px solid #e94560;font-family:sans-serif;">\
<span style="font-size:26px;vertical-align:middle;">▶</span>\
<span style="color:#e94560;font-size:15px;font-weight:bold;\
vertical-align:middle;margin:0 8px;">{ext_label}</span>\
<span style="color:#eee;font-size:14px;vertical-align:middle;">\
Open Media &nbsp;|&nbsp; پخش رسانه</span>\
<br/><span style="color:#aaa;font-size:11px;display:block;margin-top:6px;\
direction:rtl;text-align:right;">\
برای پخش ضربه بزنید &nbsp;·&nbsp; Tap to open\
</span></a>"""


def _make_media_banner(url: str, ext: str) -> str:
    """
    Render the bilingual media banner for a committed GitHub raw URL.

    ext_label shows the file format (e.g. "MP4", "MP3", "GIF") in the accent
    colour so the reader immediately knows the media type before tapping.
    """
    return _MEDIA_BANNER_TEMPLATE.format(url=url, ext_label=ext.upper())


# ---------------------------------------------------------------------------
# Manifest helper
# ---------------------------------------------------------------------------

def _load_manifest() -> dict:
    """
    Read the bridge manifest (channel/message_id → local file path).
    Returns {} on missing or malformed file.
    """
    try:
        with open(MANIFEST_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


# ---------------------------------------------------------------------------
# Content-addressable cache helpers
# ---------------------------------------------------------------------------

def _cdn_hash(url: str) -> str:
    """
    Stable MD5 of a normalised CDN URL (query strings and &amp; stripped).

    Must be identical to the hashing logic used anywhere else in the project
    that generates filenames from CDN URLs, so previously-cached files are
    always found on repeat runs.
    """
    clean = url.split("?")[0].replace("&amp;", "&")
    return hashlib.md5(clean.encode()).hexdigest()


def _find_cached(h: str):
    """
    Scan MEDIA_DIR for a committed file whose stem equals h (any extension).
    Returns (path, ext) when found, (None, None) otherwise.
    The .tmp guard prevents partially-written files from being served.
    """
    for name in os.listdir(MEDIA_DIR):
        stem, _, ext = name.rpartition(".")
        if stem == h and not name.endswith(".tmp"):
            return f"{MEDIA_DIR}/{name}", ext.lower()
    return None, None


# ---------------------------------------------------------------------------
# Generic media download  (images AND video/audio/GIF)
# ---------------------------------------------------------------------------

def _fetch_media(url: str, h: str, ext: str):
    """
    Download any media file from a CDN URL and save it as feeds/media/<h>.<ext>.

    Enforces MAX_DOWNLOAD_BYTES to avoid filling the Actions runner disk with
    large video files that bridge.py was unable to pre-fetch.

    Validation:
      • Content-Length header check before downloading (avoids wasting bandwidth).
      • Minimum size check (< 512 bytes → almost certainly an error page).
      • HTML sniff on the first 256 bytes (CDN sometimes returns an error page
        with a 200 status instead of a real 404).

    Returns (path, ext) on success, (None, None) on any failure.
    """
    try:
        req = urllib.request.Request(url, headers=_DL_HEADERS)

        with urllib.request.urlopen(req, timeout=60) as resp:
            # Honour Content-Length before reading the body — avoids
            # downloading a 500 MB file only to discard it at the size check.
            content_length = resp.headers.get("Content-Length")
            if content_length and int(content_length) > MAX_DOWNLOAD_BYTES:
                print(
                    f"  [skip] {url[:80]}… — "
                    f"Content-Length {int(content_length)//1024//1024} MB "
                    f"exceeds {MAX_DOWNLOAD_BYTES//1024//1024} MB limit",
                    file=sys.stderr,
                )
                return None, None

            data = resp.read()

        # Reject suspiciously small payloads or HTML error pages
        if len(data) < 512 or b"<html" in data[:256].lower():
            return None, None

        # Double-check actual size after download (Content-Length can be absent)
        if len(data) > MAX_DOWNLOAD_BYTES:
            print(
                f"  [skip] downloaded file is "
                f"{len(data)//1024//1024} MB — discarding",
                file=sys.stderr,
            )
            return None, None

        path = f"{MEDIA_DIR}/{h}.{ext}"
        with open(path, "wb") as fh:
            fh.write(data)
        return path, ext

    except Exception as exc:
        print(f"  [warn] media download failed {url}: {exc}", file=sys.stderr)
        return None, None


# ---------------------------------------------------------------------------
# RSS tag builders
# ---------------------------------------------------------------------------

def _enclosure(url: str, ext: str) -> str:
    """
    Build an RSS 2.0 <enclosure> element.
    The length attribute is required by spec; we use a plausible estimate
    because the actual file size is not available at this point.
    All major RSS readers accept approximate values.
    """
    length = "10000000" if ext in VIDEO_EXTS else (
             "3000000"  if ext in AUDIO_EXTS else "204800")
    mime   = MIME.get(ext, "application/octet-stream")
    return f'<enclosure url="{url}" type="{mime}" length="{length}" />'


def _media_content(url: str, ext: str) -> str:
    """
    Build a Media RSS <media:content> element.
    The `medium` attribute (video / audio / image) is Feeder's primary hint
    for choosing the correct renderer for the post card.
    """
    medium = ("video" if ext in VIDEO_EXTS
              else "audio" if ext in AUDIO_EXTS
              else "image")
    mime = MIME.get(ext, "application/octet-stream")
    return f'<media:content url="{url}" type="{mime}" medium="{medium}" />'


# ---------------------------------------------------------------------------
# Core per-item transformer
# ---------------------------------------------------------------------------

def _process_item(body: str, slug: str, raw_base: str,
                  placeholder: str, manifest: dict) -> str:
    """
    Rewrite all media URLs inside one <item> block and rebuild media RSS tags.

    Called by a re.sub() in main() — the <item> wrapper tags are NOT part of body.

    For every media URL found:
      1. Try bridge manifest (MTProto pre-download — fastest, no CDN hit).
      2. Try local cache (committed in a previous run).
      3. Try CDN live download (new file — stored and committed this run).
      If all three fail (e.g. file too large), the original CDN URL is kept
      as-is; it may not load in Iran, but the post content is not lost.

    After URL resolution, the best (or only) media asset is used to build
    <enclosure> and <media:content> tags.  For video/audio/GIF posts a
    bilingual styled banner is also injected into <description>.
    """
    # ── Strip stale enclosure/media tags ─────────────────────────────────────
    # RSSHub sometimes emits half-formed tags; rebuilding from scratch is safer.
    body = re.sub(r"<enclosure[^>]*/>\s*",     "", body, flags=re.IGNORECASE)
    body = re.sub(r"<media:content[^>]*/>\s*", "", body, flags=re.IGNORECASE)

    # ── Extract t.me permalink for manifest key construction ─────────────────
    # The canonical t.me/<channel>/<id> link is present in every RSSHub item.
    link_m   = re.search(r"https://t\.me/([^/\"<\s]+)/(\d+)", body)
    msg_chan = link_m.group(1) if link_m else slug
    msg_id   = link_m.group(2) if link_m else None

    # best_url / best_ext: the "primary" media asset for this post.
    # Used to build the final <enclosure> and <media:content> tags.
    best_url = None
    best_ext = None

    seen = set()   # de-duplicate URLs (RSSHub occasionally repeats them)

    for raw_url in _URL_RE.findall(body):
        if raw_url in seen:
            continue
        seen.add(raw_url)

        # ── Strip Unsplash foreign placeholders ───────────────────────────────
        # RSSHub injects Unsplash images for text-only posts (no file extension).
        # Remove the wrapping <img> tag and the bare URL from the body so the
        # post falls through to the local placeholder path below.
        # Wrapped in try/except so a malformed match never crashes the pipeline.
        if "unsplash.com" in raw_url.lower():
            try:
                body = _UNSPLASH_IMG_RE.sub("", body)
                body = body.replace(raw_url, "")
            except Exception as exc:
                print(f"  [warn] unsplash strip failed: {exc}", file=sys.stderr)
            continue   # never set best_url — fall through to placeholder

        # Normalise: strip query string tokens before extension detection / hashing
        clean = raw_url.split("?")[0].replace("&amp;", "&")

        # Infer extension — telesco.pe bare links are always video (mp4)
        ext_m = re.search(r"\.([a-z0-9]{2,4})$", clean, re.IGNORECASE)
        ext   = ext_m.group(1).lower() if ext_m else (
                "mp4" if "telesco.pe" in clean else None)

        if not ext or ext not in ALL_MEDIA_EXTS:
            continue   # unrecognised or unsupported — leave untouched

        # ── Priority 1: bridge manifest ───────────────────────────────────────
        # bridge.py stores ALL media types (not just images) in the manifest
        # since this version.  This is the preferred path for everything.
        manifest_key = f"{msg_chan}/{msg_id}"
        if msg_id and manifest_key in manifest:
            local = manifest[manifest_key]
            if os.path.exists(local):
                fname  = os.path.basename(local)
                # The local file may have a different extension than `ext` if
                # bridge.py saved it with the correct MIME-derived extension.
                actual_ext = fname.rsplit(".", 1)[-1].lower() if "." in fname else ext
                gh_url = f"{raw_base}/{MEDIA_DIR}/{fname}"
                body   = body.replace(raw_url, gh_url)
                best_url, best_ext = gh_url, actual_ext
                continue

        # ── Priority 2: local cache (previous run) ────────────────────────────
        h = _cdn_hash(raw_url)
        cached, c_ext = _find_cached(h)
        if cached:
            gh_url = f"{raw_base}/{MEDIA_DIR}/{os.path.basename(cached)}"
            body   = body.replace(raw_url, gh_url)
            best_url, best_ext = gh_url, c_ext
            continue

        # ── Priority 3: CDN live download ─────────────────────────────────────
        # Works for both images and small-to-medium video/audio files.
        # Using Python str.replace() instead of sed avoids shell-injection when
        # the URL contains & ? % or other special characters.
        path, d_ext = _fetch_media(raw_url, h, ext)
        if path:
            gh_url = f"{raw_base}/{MEDIA_DIR}/{os.path.basename(path)}"
            body   = body.replace(raw_url, gh_url)
            best_url, best_ext = gh_url, d_ext
        # If all three paths fail: original CDN URL is left in the XML as a
        # last-resort fallback.  The reader may not load it inside Iran, but
        # the text content of the post is always preserved.

    # ── Inject bilingual banner for non-image media ───────────────────────────
    # If the best media asset is video, audio, or GIF, inject a styled banner
    # at the top of the post description so the reader sees a clear, tappable
    # "Open Media | پخش رسانه" link regardless of whether their RSS reader
    # supports <media:content> inline playback.
    if best_url and best_ext and best_ext not in IMAGE_EXTS - {"gif"}:
        # GIF is in IMAGE_EXTS but deserves a play banner (it is animated).
        # Static image types (jpg, jpeg, png, webp) do NOT get a banner.
        is_animated = best_ext in VIDEO_EXTS | AUDIO_EXTS | {"gif"}
        if is_animated:
            banner = _make_media_banner(best_url, best_ext)
            body = re.sub(
                r"(<description>\s*<!\[CDATA\[)",
                lambda m, b=banner: m.group(1) + b,
                body,
            )

    # ── Build <enclosure> + <media:content> ──────────────────────────────────
    if best_url and best_ext:
        suffix = (
            f"{_enclosure(best_url, best_ext)}\n"
            f"{_media_content(best_url, best_ext)}"
        )
    else:
        # Text-only post: use placeholder so Feeder's card view is never blank.
        suffix = (
            f"{_enclosure(placeholder, 'jpg')}\n"
            f"{_media_content(placeholder, 'jpg')}"
        )
        body = re.sub(
            r"(<description>\s*<!\[CDATA\[)",
            lambda m, p=placeholder: (
                m.group(1)
                + f'<img src="{p}" style="width:100%;border-radius:8px;margin-bottom:10px" /><br/>'
            ),
            body,
        )

    return body.rstrip() + "\n" + suffix + "\n"


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    """
    Read raw RSSHub XML from stdin, process every <item>, write to stdout.
    Positional arguments are enforced strictly — this script is always called
    by Fetch-feeds.sh in a controlled environment with guaranteed argument order.
    """
    if len(sys.argv) != 4:
        sys.exit("Usage: process_feed.py <slug> <raw_base_url> <placeholder_url>")

    slug, raw_base, placeholder = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(MEDIA_DIR, exist_ok=True)

    xml = sys.stdin.read()
    if not xml:
        return   # empty input (curl timed out) — write nothing, exit cleanly

    manifest = _load_manifest()

    # ── Namespace injection ───────────────────────────────────────────────────
    # <media:content> requires the Media RSS namespace on the root <rss> element.
    # RSSHub does not always include it; we add it when absent.
    if "xmlns:media=" not in xml:
        xml = re.sub(
            r"<rss\b",
            '<rss xmlns:media="http://search.yahoo.com/mrss/"',
            xml, count=1,
        )

    # ── Per-item processing ───────────────────────────────────────────────────
    # re.DOTALL is required because <item> bodies always span multiple lines.
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
