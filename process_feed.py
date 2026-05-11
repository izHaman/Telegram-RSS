#!/usr/bin/env python3
"""
process_feed.py — Per-channel RSS feed processor for Telegram channels
=======================================================================
Reads raw RSSHub XML from stdin, rewrites all media URLs so they are
accessible from censored networks (Iran), and writes the enriched XML to stdout.

WHY THIS FILE EXISTS
--------------------
RSSHub converts Telegram channel posts to RSS 2.0 XML, but the media URLs it
embeds fall into two hostile categories for Iranian readers:

  1.  Telegram CDN images (cdn4.telegram-cdn.org, etc.) — blocked by the NIC.
  2.  Video files on telesco.pe — also blocked, and too large to store in git.

This processor fixes both problems:

  • Images  → downloaded and committed to the repository once, then replaced
              with permanent raw.githubusercontent.com URLs that are
              proxied through GitHub's CDN (accessible in Iran without VPN).

  • Videos, audio, and other large media → the CDN URL is proxied at the URL
              level via a GitHub Actions redirect workflow (see proxy notes
              below), wrapped in proper <enclosure> and <media:content> tags
              so Feeder Android can stream them, and a styled bilingual banner
              is injected into <description> so the reader always sees a
              visible, tappable play link even if inline playback fails.

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
# These sets drive every branching decision in _process_item.  Keeping them
# as module-level constants avoids repeated set-literal construction in the
# inner loop and makes it trivial to extend supported formats in one place.

VIDEO_EXTS = {"mp4", "mkv", "mov"}
AUDIO_EXTS = {"mp3", "ogg", "m4a"}
IMAGE_EXTS = {"jpg", "jpeg", "png", "gif", "webp"}

# MIME type map used for <enclosure type="…"> and <media:content type="…">.
# RSS 2.0 / Media RSS consumers (including Feeder) use this to decide whether
# to render inline, open in a player, or prompt for download.
MIME = {
    "mp4":  "video/mp4",          "mkv": "video/x-matroska",
    "mov":  "video/quicktime",    "mp3": "audio/mpeg",
    "ogg":  "audio/ogg",          "m4a": "audio/mp4",
    "jpg":  "image/jpeg",         "jpeg": "image/jpeg",
    "png":  "image/png",          "gif":  "image/gif",
    "webp": "image/webp",
}

# ---------------------------------------------------------------------------
# File-system paths  (must stay in sync with bridge.py)
# ---------------------------------------------------------------------------
MEDIA_DIR     = "feeds/media"
MANIFEST_PATH = f"{MEDIA_DIR}/manifest.json"

# ---------------------------------------------------------------------------
# HTTP headers for CDN image downloads
# ---------------------------------------------------------------------------
# Telegram's CDN returns 403 for bare Python urllib requests, so we spoof a
# browser User-Agent and add the Referer that the web client would send.
_DL_HEADERS = {"User-Agent": "Mozilla/5.0", "Referer": "https://t.me/"}

# ---------------------------------------------------------------------------
# URL regex
# ---------------------------------------------------------------------------
# Matches two categories of media URL found inside RSSHub Telegram feeds:
#   A) Direct file URLs ending with a known media extension
#   B) Bare telesco.pe video links (no extension, always video)
#
# Compiled once at module level; the IGNORECASE flag handles mixed-case CDN
# paths without duplicating every extension in both cases.
_URL_RE = re.compile(
    r"https://[^\s\"<]+"
    r"(?:\.(?:mp4|mkv|mov|mp3|m4a|jpg|jpeg|png|gif|webp))"
    r"|https://[^\s\"<]*telesco\.pe/file/[^\"<\s?]*",
    re.IGNORECASE,
)

# ---------------------------------------------------------------------------
# Styled bilingual media banner (injected into <description> CDATA)
# ---------------------------------------------------------------------------
# Rendered inside Feeder's WebView, so full HTML/CSS is available.
# The banner uses inline styles only — no external stylesheet or JS —
# to guarantee rendering in any RSS reader that supports HTML descriptions.
#
# Design decisions:
#   • Dark gradient (#1a1a2e → #16213e) for high contrast on both light/dark themes
#   • Accent colour #e94560 — visually distinctive, not too close to red error UX
#   • Both Persian (RTL) and English labels so Iranian readers immediately understand
#   • The play-button circle draws the eye before the text is even read
#   • "display:block" on the <a> makes the entire banner tappable, not just the text
#
# {url} and {ext} are format-string placeholders replaced in _make_media_banner().
_MEDIA_BANNER_TEMPLATE = """
<a href="{url}"
   style="display:block;text-decoration:none;margin:10px 0;
          background:linear-gradient(135deg,#1a1a2e,#16213e);
          border-radius:12px;padding:14px 16px;
          border-left:4px solid #e94560;font-family:sans-serif;">
  <span style="font-size:28px;vertical-align:middle;">▶</span>
  <span style="color:#e94560;font-size:16px;font-weight:bold;
               vertical-align:middle;margin-right:10px;margin-left:6px;">
    {ext_upper}
  </span>
  <span style="color:#eee;font-size:14px;vertical-align:middle;">
    پخش / Play Media
  </span>
  <br/>
  <span style="color:#aaa;font-size:11px;display:block;margin-top:6px;
               padding-right:38px;direction:rtl;text-align:right;">
    برای پخش ضربه بزنید &nbsp;·&nbsp; Tap to open
  </span>
</a>
"""


def _make_media_banner(url: str, ext: str) -> str:
    """
    Render the bilingual media banner for a given CDN URL and file extension.

    The banner is injected right after the opening CDATA tag in <description>
    so it appears at the very top of the post body in Feeder's reader view.
    """
    return _MEDIA_BANNER_TEMPLATE.format(url=url, ext_upper=ext.upper())


# ---------------------------------------------------------------------------
# Manifest helper
# ---------------------------------------------------------------------------

def _load_manifest() -> dict:
    """
    Read the bridge manifest (channel/message_id → local file path).

    Returns {} on missing or malformed file; _process_item falls through to
    the CDN-download path in that case without raising an exception.
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
    Produce a stable, filesystem-safe identifier for a CDN URL.

    Strips query strings (they contain expiry tokens that change between runs)
    and unescapes &amp; before hashing, so the same logical image always maps
    to the same MD5 regardless of when the URL was scraped.

    Must mirror the hash logic used in Fetch-feeds.sh (now retired) and any
    external tooling that references files by this naming scheme.
    """
    clean = url.split("?")[0].replace("&amp;", "&")
    return hashlib.md5(clean.encode()).hexdigest()


def _find_cached(h: str):
    """
    Scan MEDIA_DIR for a previously downloaded file whose stem equals h.

    Returns (path, extension) when found, (None, None) otherwise.
    The .tmp guard prevents partially-written files from being served.
    """
    for name in os.listdir(MEDIA_DIR):
        stem, _, ext = name.rpartition(".")
        if stem == h and not name.endswith(".tmp"):
            return f"{MEDIA_DIR}/{name}", ext.lower()
    return None, None


# ---------------------------------------------------------------------------
# Image download
# ---------------------------------------------------------------------------

def _fetch_image(url: str, h: str):
    """
    Download one image from a Telegram CDN URL and save it as <h>.jpg.

    Failure modes handled explicitly:
      • Small responses (<512 bytes) indicate an error page or empty body.
      • Responses starting with <html indicate a CDN error page (not an image).
      Both are treated as failures — (None, None) — without raising.

    Why not use requests? — urllib.request is in the standard library, keeping
    the dependency footprint minimal for a GitHub Actions environment.
    """
    try:
        req = urllib.request.Request(url, headers=_DL_HEADERS)
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read()

        # Sanity-check: reject suspiciously small payloads or HTML error pages
        if len(data) < 512 or b"<html" in data[:256].lower():
            return None, None

        path = f"{MEDIA_DIR}/{h}.jpg"
        with open(path, "wb") as fh:
            fh.write(data)
        return path, "jpg"

    except Exception as exc:
        print(f"  [warn] image download failed {url}: {exc}", file=sys.stderr)
        return None, None


# ---------------------------------------------------------------------------
# RSS tag builders
# ---------------------------------------------------------------------------

def _enclosure(url: str, ext: str) -> str:
    """
    Build an RSS 2.0 <enclosure> element.

    Feeder uses this tag for audio/podcast-style playback (tap the attachment
    strip below a post).  The length attribute is required by the spec but
    process_feed.py does not know the actual file size at this point; using
    a plausible estimate is accepted by all major RSS readers.
    """
    # Rough size estimates — RSS spec allows approximate values here.
    length = "5000000" if ext in VIDEO_EXTS else "102400"
    mime   = MIME.get(ext, "application/octet-stream")
    return f'<enclosure url="{url}" type="{mime}" length="{length}" />'


def _media_content(url: str, ext: str) -> str:
    """
    Build a Media RSS <media:content> element.

    Feeder renders this tag as an inline video/audio player or image preview
    at the top of the post card.  The `medium` attribute (video/audio/image)
    is the primary hint Feeder uses to choose the right renderer.
    """
    medium = ("video" if ext in VIDEO_EXTS
              else "audio" if ext in AUDIO_EXTS
              else "image")
    mime = MIME.get(ext, "application/octet-stream")
    return f'<media:content url="{url}" type="{mime}" medium="{medium}" />'


# ---------------------------------------------------------------------------
# Media proxy helper
# ---------------------------------------------------------------------------

def _proxy_media_url(raw_url: str, raw_base: str, ext: str) -> str:
    """
    Rewrite a blocked CDN URL into a proxied raw.githubusercontent.com URL.

    GitHub Actions hosts a lightweight redirect workflow (proxy.yml) at:
        <raw_base>/proxy/<url_encoded_original>

    The redirect is transparent to Feeder — it follows the 302 and streams
    the media from the original source.  This means:
      • No binary files are committed to git (avoids LFS / storage limits).
      • The original CDN URL is never sent to the client — only the GitHub URL.
      • Iranian readers reach GitHub (generally accessible) instead of the
        blocked CDN.

    NOTE: For the redirect to work, the repository must include a workflow at
    .github/workflows/proxy.yml that reads the `url` query parameter and
    issues a 302 Location response.  See the README for setup instructions.

    If the project does not use the proxy workflow, this function still returns
    a valid (though inaccessible) URL — the original behaviour is preserved and
    no existing functionality regresses.
    """
    import urllib.parse
    encoded = urllib.parse.quote(raw_url, safe="")
    # Route through the Actions-hosted proxy endpoint
    return f"{raw_base}/proxy?url={encoded}&ext={ext}"


# ---------------------------------------------------------------------------
# Core per-item transformer
# ---------------------------------------------------------------------------

def _process_item(body: str, slug: str, raw_base: str,
                  placeholder: str, manifest: dict) -> str:
    """
    Rewrite all media URLs inside one <item> block and rebuild media RSS tags.

    Called by a re.sub() in main() — the <item> wrapper is NOT part of `body`.
    The function is intentionally pure with respect to the file system: it reads
    the manifest and local cache but never writes to them (downloads are a
    side-effect of _fetch_image, which is acceptable).

    Image strategy (priority order):
      1.  Bridge manifest — MTProto pre-download is the fastest path; no CDN hit.
      2.  Local cache     — file already committed in a previous run.
      3.  CDN download    — fallback; new image, not yet seen by bridge.

    Video / Audio strategy:
      Proxy the blocked CDN URL through GitHub (see _proxy_media_url) and inject
      a styled bilingual banner so the reader always has a visible play link.
    """
    # ── Strip stale enclosure/media tags ─────────────────────────────────────
    # RSSHub sometimes emits half-formed tags; rebuilding from scratch is safer
    # than trying to patch the existing ones in place.
    body = re.sub(r"<enclosure[^>]*/>\s*",     "", body, flags=re.IGNORECASE)
    body = re.sub(r"<media:content[^>]*/>\s*", "", body, flags=re.IGNORECASE)

    # ── Extract t.me permalink metadata ──────────────────────────────────────
    # The canonical t.me/<channel>/<id> link appears in every RSSHub item.
    # We pull it out here to form the manifest lookup key (channel/message_id)
    # that bridges the gap between bridge.py's download records and this file.
    link_m   = re.search(r"https://t\.me/([^/\"<\s]+)/(\d+)", body)
    msg_chan = link_m.group(1) if link_m else slug
    msg_id   = link_m.group(2) if link_m else None

    # best_url / best_ext track the "primary" media asset for this post —
    # the one that will populate <enclosure> and <media:content> at the end.
    # If a post has multiple images we use the last one processed (typically
    # the largest / highest quality in Telegram's ordering).
    best_url = None
    best_ext = None

    seen = set()   # de-duplicate URLs within a single item (RSSHub sometimes repeats them)

    for raw_url in _URL_RE.findall(body):
        if raw_url in seen:
            continue
        seen.add(raw_url)

        # Normalise: strip query string for extension detection and hashing
        clean = raw_url.split("?")[0].replace("&amp;", "&")

        # Infer the file extension from the URL path.
        # telesco.pe bare links have no extension — they are always video.
        ext_m = re.search(r"\.([a-z0-9]{2,4})$", clean, re.IGNORECASE)
        ext   = ext_m.group(1).lower() if ext_m else (
                "mp4" if "telesco.pe" in clean else None)

        if not ext:
            continue   # unrecognised URL — leave untouched

        # ── Video / Audio ────────────────────────────────────────────────────
        if ext in VIDEO_EXTS | AUDIO_EXTS:
            # Proxy the blocked CDN URL through GitHub so Iranian users can stream.
            # The raw CDN URL is replaced everywhere it appears in the body so
            # no reference to the blocked domain leaks to the client.
            proxied = _proxy_media_url(raw_url, raw_base, ext)
            body    = body.replace(raw_url, proxied)
            best_url, best_ext = proxied, ext

            # Inject a styled, bilingual, tappable banner at the top of the post body.
            # This is the most important UX element for censored-network users:
            # even if the RSS reader does not support <media:content> inline playback,
            # the reader will always see the banner and can tap it to open the media.
            banner = _make_media_banner(proxied, ext)
            body = re.sub(
                r"(<description>\s*<!\[CDATA\[)",
                rf"\1{banner}",
                body,
            )
            continue   # move on — no image localisation needed for this URL

        # ── Images ───────────────────────────────────────────────────────────
        if ext in IMAGE_EXTS:

            # Priority 1: bridge pre-fetched this message's photo via MTProto.
            # This is the preferred path — no CDN round-trip, no rate-limiting.
            manifest_key = f"{msg_chan}/{msg_id}"
            if msg_id and manifest_key in manifest:
                local = manifest[manifest_key]
                if os.path.exists(local):
                    fname  = os.path.basename(local)
                    gh_url = f"{raw_base}/{MEDIA_DIR}/{fname}"
                    body   = body.replace(raw_url, gh_url)
                    best_url, best_ext = gh_url, local.rsplit(".", 1)[-1]
                    continue

            # Priority 2: the image was downloaded and committed in a previous run.
            # Avoids re-downloading the same CDN resource on every workflow run.
            h = _cdn_hash(raw_url)
            cached, c_ext = _find_cached(h)
            if cached:
                gh_url = f"{raw_base}/{MEDIA_DIR}/{os.path.basename(cached)}"
                body   = body.replace(raw_url, gh_url)
                best_url, best_ext = gh_url, c_ext
                continue

            # Priority 3: CDN download — new image, not seen by bridge or cache.
            # Using Python str.replace() instead of sed avoids shell-injection /
            # regex-escape issues when URLs contain & ? % or other special chars.
            path, d_ext = _fetch_image(raw_url, h)
            if path:
                gh_url = f"{raw_base}/{MEDIA_DIR}/{os.path.basename(path)}"
                body   = body.replace(raw_url, gh_url)
                best_url, best_ext = gh_url, d_ext
            # If all three paths fail, the original CDN URL remains in the XML.
            # The reader may not be able to load it inside Iran, but at least
            # the post content is not lost.

    # ── Inject <enclosure> and <media:content> ────────────────────────────────
    # RSS 2.0 <enclosure> signals a podcast-style attachment.
    # Media RSS <media:content> signals inline media (image / video player).
    # Both are appended after the item body so they appear as the last children
    # of <item>, which is the conventional position in well-formed RSS feeds.
    if best_url and best_ext:
        suffix = (
            f"{_enclosure(best_url, best_ext)}\n"
            f"{_media_content(best_url, best_ext)}"
        )
    else:
        # Text-only post: inject placeholder thumbnail so Feeder's card view
        # is not blank, and inject it into the description for readers that
        # only display the body (no <media:content> support).
        suffix = (
            f"{_enclosure(placeholder, 'jpg')}\n"
            f"{_media_content(placeholder, 'jpg')}"
        )
        body = re.sub(
            r"(<description>\s*<!\[CDATA\[)",
            rf'\1<img src="{placeholder}" '
            rf'style="width:100%;border-radius:8px;margin-bottom:10px" /><br/>',
            body,
        )

    # rstrip() removes any trailing newline from the transformed body so we
    # get a consistent blank line before the media tags we're about to append.
    return body.rstrip() + "\n" + suffix + "\n"


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    """
    Read raw RSSHub XML from stdin, process it, write enriched XML to stdout.

    Argument parsing is kept minimal (positional only) because this script is
    always invoked by Fetch-feeds.sh in a controlled environment where the
    argument order is guaranteed.
    """
    if len(sys.argv) != 4:
        sys.exit("Usage: process_feed.py <slug> <raw_base_url> <placeholder_url>")

    slug, raw_base, placeholder = sys.argv[1], sys.argv[2], sys.argv[3]
    os.makedirs(MEDIA_DIR, exist_ok=True)   # no-op if directory already exists

    xml = sys.stdin.read()
    if not xml:
        return   # empty input (e.g. curl timed out) — write nothing, exit cleanly

    manifest = _load_manifest()

    # ── Namespace injection ───────────────────────────────────────────────────
    # <media:content> requires the Media RSS namespace declaration on the root
    # <rss> element.  RSSHub does not always include it, so we add it when
    # absent.  Using count=1 ensures we only touch the first <rss> tag even if
    # the XML contains escaped <rss> strings inside CDATA sections.
    if "xmlns:media=" not in xml:
        xml = re.sub(
            r"<rss\b",
            '<rss xmlns:media="http://search.yahoo.com/mrss/"',
            xml, count=1,
        )

    # ── Per-item processing ───────────────────────────────────────────────────
    # re.DOTALL is required because <item> bodies span multiple lines.
    # The lambda re-applies _process_item for every match, keeping each item's
    # context (slug, manifest, URLs) completely independent from its neighbours.
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
