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
# Matches two categories of media URL found inside RSSHub Telegram feeds:
#   A) Direct file URLs ending with a known media extension
#   B) Bare telesco.pe video links (no extension in path, always video)
_URL_RE = re.compile(
    r"https://(?:(?!&quot;)[^\s\"<])+"
    r"(?:\.(?:mp4|mkv|mov|webm|mp3|m4a|ogg|jpg|jpeg|png|gif|webp))"
    r"|https://(?:(?!&quot;)[^\s\"<])*telesco\.pe/file/(?:(?!&quot;)[^\s\"<?])*",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Bilingual media link
# ---------------------------------------------------------------------------
# A plain-text hyperlink injected into <description> CDATA for every
# video, audio, or GIF post.  Feeder (and most RSS readers) does NOT render
# complex inline-CSS blocks inside CDATA, but always renders a bare <a> tag.
# The «» decorators make the link visually distinct without any CSS.

def _make_media_link(url: str, ext: str) -> str:
    """
    Build a simple, universally-renderable hyperlink for non-image media.

    Format:  ««  Show media | پخش رسانه  [EXT]  »»
    The link text is plain ASCII + Persian — no CSS, no spans, no JavaScript.
    Feeder, Reeder, NetNewsWire and virtually every other RSS reader will show
    this as a tappable underlined link.
    """
    label = f"«« Show media | پخش رسانه [{ext.upper()}] »»"
    return f'<a href="{url}">{label}</a><br/>'


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
            raw_url = raw_url.replace("&quot;", "").replace("&#34;", "")
            if raw_url in seen:
                continue
            seen.add(raw_url)
                    
            # Normalise: strip query string tokens before extension detection / hashing
            clean = raw_url.split("?")[0].replace("&amp;", "&").replace("&quot;", "").replace("&#34;", "")

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

    # ── Inject media link for video / audio / GIF posts ──────────────────────
    # Static images (jpg, jpeg, png, webp) do NOT get a link — the image itself
    # is already visible in the feed card.  GIF is animated → gets a link.
    #
    # RSSHub produces two description formats:
    #   A) <description><![CDATA[...]]></description>   (CDATA-wrapped)
    #   B) <description><p>...</p></description>         (plain HTML, no CDATA)
    # The regex below handles BOTH by matching <description> then optionally
    # the CDATA opener, inserting the link text right after whichever is found.
    # repl is a lambda (not an rf-string) to prevent regex engine from
    # misinterpreting backslashes or & characters inside the URL.
    ANIMATED_EXTS = VIDEO_EXTS | AUDIO_EXTS | {"gif"}
    if best_url and best_ext and best_ext in ANIMATED_EXTS:
        _link = _make_media_link(best_url, best_ext)
        body = re.sub(
            r"(<description>)(\s*(?:<!\[CDATA\[)?)",
            lambda m: m.group(1) + m.group(2) + _link,
            body,
            count=1,
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
        _ph = placeholder
        body = re.sub(
            r"(<description>)(\s*(?:<!\[CDATA\[)?)",
            lambda m: m.group(1) + m.group(2) + (
                f'<img src="{_ph}" '
                f'style="width:100%;border-radius:8px;margin-bottom:10px" /><br/>'
            ),
            body,
            count=1,
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
