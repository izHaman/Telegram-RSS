<div align="center">

<h1>📡 Smart Telegram Content-Reader</h1>

<p><em>A fully automated GitHub Actions pipeline that mirrors Telegram channels to permanent, censorship-resistant RSS feeds — accessible without a VPN from anywhere in the world.</em></p>

---

### 🌐 Language / زبان

[![English](https://img.shields.io/badge/README-English-blue?style=for-the-badge&logo=github)](#) &nbsp;&nbsp; [![Farsi](https://img.shields.io/badge/README-Farsi-green?style=for-the-badge&logo=github)](./README_Fa.md)

---

[![GitHub Actions](https://img.shields.io/badge/Automated-GitHub%20Actions-2088FF?style=flat-square&logo=github-actions&logoColor=white)](https://github.com/features/actions)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org/)
[![Telegram MTProto](https://img.shields.io/badge/Telegram-MTProto%20API-26A5E4?style=flat-square&logo=telegram&logoColor=white)](https://core.telegram.org/mtproto)
[![RSSHub](https://img.shields.io/badge/RSSHub-Compatible-FF6600?style=flat-square)](https://rsshub.app/)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](./LICENSE)

</div>

---

## 📋 Table of Contents

- [What Is This?](#-what-is-this)
- [How It Works](#-how-it-works)
- [Features](#-features)
- [Architecture Overview](#-architecture-overview)
- [Pipeline Stages](#-pipeline-stages)
- [Channel Rotation System](#-channel-rotation-system)
- [Media Resolution Strategy](#-media-resolution-strategy)
- [Censorship Circumvention](#-censorship-circumvention)
- [RSS Feed Enrichment](#-rss-feed-enrichment)
- [Setup & Configuration](#-setup--configuration)
- [Secrets Reference](#-secrets-reference)
- [Adding Channels](#-adding-channels)
- [File Structure](#-file-structure)
- [Size & Storage Policy](#-size--storage-policy)
- [Compatibility](#-compatibility)
- [Release Description](#-release-description)
- [Contributing](#-contributing)

---

## 🔭 What Is This?

**Smart Telegram Content-Reader** is a zero-infrastructure RSS bridge that converts Telegram public channels into fully self-hosted, permanent RSS feeds — with all media files (images, videos, audio, GIFs) committed directly into the repository, reachable via raw GitHub URLs.

The key problem it solves: Telegram CDN URLs are **ephemeral** (they expire within hours) and **geo-blocked** in countries like Iran. Standard RSSHub feeds embed these short-lived CDN links, making the media inaccessible to a large portion of the audience.

This pipeline eliminates that problem entirely by:

1. Authenticating to Telegram via the official MTProto API to **pre-download all media** before CDN links expire.
2. Committing those files to the repository so they become **permanent `raw.githubusercontent.com` URLs** that bypass censorship.
3. Rewriting every feed's XML on-the-fly so readers see stable, working links — **no VPN required**.

---

## ⚙️ How It Works

```
┌─────────────────────────────────────────────────────┐
│                  GitHub Actions Cron                │
│              (every 30 minutes, auto)               │
└──────────────────────┬──────────────────────────────┘
                       │
          ┌────────────▼────────────┐
          │   Step 1: bridge.py     │  ← MTProto auth via Telethon
          │  Telegram Media Bridge  │  ← Downloads images, video,
          │                         │    audio, GIFs for all channels
          └────────────┬────────────┘
                       │  manifest.json written
          ┌────────────▼────────────┐
          │  Step 2: Fetch-feeds.sh │  ← Rotates through channels
          │   RSSHub XML Fetcher    │  ← 4 channels per run (chunk)
          │                         │  ← Multi-instance fallback
          └────────────┬────────────┘
                       │  raw RSSHub XML
          ┌────────────▼────────────┐
          │  Step 3: process_feed.py│  ← Rewrites all media URLs
          │   Feed Processor/Enrich │  ← Injects enclosure tags
          │                         │  ← Injects bilingual banners
          └────────────┬────────────┘
                       │
          ┌────────────▼────────────┐
          │   git commit & push     │  ← Permanent raw.githubusercontent.com
          │   feeds/<channel>.xml   │    URLs now live in the repo
          └─────────────────────────┘
```

---

## ✨ Features

### 🔐 Telegram MTProto Integration
- Authenticates to Telegram's official API using **Telethon** (MTProto protocol) — not screen scraping or unofficial endpoints.
- Downloads the **10 most recent messages** per channel on every run.
- Supports all media types: **images, videos, audio files, GIFs, and documents**.
- Uses a serialised `StringSession` stored as a GitHub Secret — no `.session` files on disk, no persistent authentication state.

### 📦 Intelligent Media Caching & Manifest System
- Maintains a `manifest.json` that maps every `channel/message_id` pair to a local file path.
- **Deduplication**: files already downloaded are never downloaded again — the manifest is checked before any network call.
- **Content-addressable local cache**: previous-run files are found by MD5 hash of the CDN URL, so they survive even if the feed XML changes.
- Manifest is written atomically (once, after all channels) to prevent partial/corrupt states.

### 🔄 Three-Tier Media Resolution
For every media URL found in a feed, the processor tries three strategies in priority order:
1. **Bridge Manifest** — MTProto pre-downloaded file (fastest, no CDN hit)
2. **Local Cache** — file committed in a previous run (hash-based lookup)
3. **Live CDN Download** — real-time download with size gating and HTML-error detection

If all three fail, the original CDN URL is preserved as a last-resort fallback.

### 🌍 Censorship-Resistant URLs
- All committed media is served from `raw.githubusercontent.com` — accessible without a VPN in censored networks (Iran, etc.).
- CDN URLs (Telegram's `cdn*.telegram-cdn.org` and `telesco.pe`) are fully replaced in the final XML.
- Placeholder thumbnail injected for text-only posts so feed cards are never blank.

### 📡 Multi-Instance RSSHub Fallback
- Tries **three public RSSHub instances** in sequence per channel.
- Falls back automatically if the primary instance returns a media-stripped or rate-limited response.
- Detection heuristic: checks for `mp4`, `video`, or `telesco.pe` in the response to confirm a media-rich feed was received.

### 🗂️ Channel Rotation System
- Maintains a **cursor in `state.json`** that advances by 4 channels per run.
- With 12 total channels, every channel is refreshed every 3 runs (~90 minutes).
- Modulo arithmetic wraps the cursor safely — no index-out-of-bounds errors.
- Balances freshness against GitHub Actions usage and RSSHub rate limits.

### 🖼️ Image Optimisation
- Downloaded JPEG/PNG images are re-encoded at **70% JPEG quality** using Pillow.
- Typically reduces file size by **50–60%** with no visible artefact on mobile screens.
- Alpha-channel images are safely converted to RGB before JPEG encoding.
- GIFs, videos, and audio are stored verbatim (no re-encoding).

### 📰 RSS Feed Enrichment (Media RSS)
- Injects proper `<enclosure>` elements (RSS 2.0 spec) for every post with media.
- Injects `<media:content>` elements (Yahoo Media RSS) with correct `medium` attribute (`video` / `audio` / `image`).
- Injects the `xmlns:media` namespace on the `<rss>` root if RSSHub omitted it.
- Accurate MIME types for all supported formats (mp4, mkv, mov, webm, mp3, ogg, m4a, jpg, png, gif, webp).

### 🎬 Bilingual Media Banner
- For every **video, audio, or GIF** post, a styled HTML banner is injected into `<description>`.
- Renders in any WebView-based RSS reader (Feeder, Reeder, NetNewsWire, etc.).
- **Bilingual**: English + Persian (`پخش رسانه | Open Media`).
- Pure inline CSS — no JavaScript, no external requests, dark-gradient design.
- Entire banner is tappable — no tiny hit targets.

### 🧹 Automatic Media Pruning
- Files older than **48 hours** that are **not tracked by git** are automatically deleted.
- Git-tracked files (live in feed URLs) are never touched.
- Prevents the `feeds/media/` directory from growing without bound across runs.

### 🛡️ Robust Error Handling
- `set -euo pipefail` in the shell script — any unhandled error aborts the pipeline.
- Per-channel errors (empty response, download failure) are logged as warnings and skipped — one bad channel never blocks the others.
- Bridge is a **graceful no-op** when Telegram secrets are absent (safe for forks and PRs).
- CDN download validation: Content-Length pre-check, minimum-size check, HTML-error-page sniff.
- Image optimisation errors are swallowed — a bad optimise never crashes the pipeline.

### 🔒 Size & Storage Gating
- **MTProto bridge**: 50 MB per-file hard limit (below GitHub's 100 MB single-file ceiling).
- **CDN fallback downloader**: separate 50 MB limit to prevent disk exhaustion on Actions runners.
- Large files are skipped with an informational log entry — their original CDN URL is preserved as fallback.

---

## 🏗️ Architecture Overview

| Component | File | Role |
|---|---|---|
| Workflow Orchestrator | `fetch.yml` | GitHub Actions cron/dispatch trigger |
| Media Bridge | `bridge.py` | MTProto auth, media download, manifest |
| Pipeline Entrypoint | `Fetch-feeds.sh` | Orchestrates all 3 steps, git commit |
| Feed Processor | `process_feed.py` | URL rewriting, XML enrichment |
| Rotation State | `state.json` | Cursor for channel chunk rotation |
| Dependencies | `requirements.txt` | Pillow, Telethon |

---

## 🔬 Pipeline Stages

### Stage 1 — `bridge.py`: Telegram Media Bridge

Runs **before** any RSSHub fetching. Opens a Telethon `TelegramClient` authenticated via a serialised `StringSession`. For each configured channel, iterates the 10 most recent messages and downloads any media not already in the manifest.

**Supported media types**: `image/jpeg`, `image/png`, `image/gif`, `image/webp`, `video/mp4`, `video/mkv`, `video/mov`, `video/webm`, `audio/mpeg`, `audio/ogg`, `audio/mp4`.

**Naming scheme**: `feeds/media/tg_<channel>_<message_id>.<ext>`

**MIME → extension resolution**: A custom lookup table with stdlib `mimetypes` fallback ensures the saved filename always reflects the true format.

---

### Stage 2 — `Fetch-feeds.sh`: RSSHub Fetcher

Reads the cursor from `state.json`, computes the 4-channel chunk for this run, and fetches each channel's RSS XML from RSSHub with a multi-instance fallback loop.

```bash
RSSHUB_INSTANCES=(
    "https://rsshub.rssforever.com"   # primary
    "https://rsshub.moeyy.cn"         # secondary
    "https://rsshub.app"              # official (rate-limited)
)
```

Each `curl` call sets `--connect-timeout 15` and `--max-time 60`. The response is validated for media indicators before accepting it.

---

### Stage 3 — `process_feed.py`: Feed Processor

Reads raw XML from stdin, processes every `<item>`, writes enriched XML to stdout. Key transformations per item:

- Strip stale `<enclosure>` and `<media:content>` tags.
- Extract `t.me/<channel>/<id>` permalink to build the manifest lookup key.
- For each media URL matched by the regex:
  - Try manifest → try cache → try CDN download.
  - Replace URL in XML body with permanent GitHub raw URL.
- Inject bilingual banner for animated/audio media.
- Build and append `<enclosure>` + `<media:content>` tags.
- Inject placeholder image for text-only posts.

---

## 🔄 Channel Rotation System

```
Channels (12 total):
mamlekate | ircfspace | vahidonline | iranintltv | drtel | hatricktv
iholymaryat70 | jadivarlog | digitechirchannel | whynationsfail2019
khateraaat | dw_farsi

Run 0: [0..3]  → mamlekate, ircfspace, vahidonline, iranintltv
Run 1: [4..7]  → drtel, hatricktv, iholymaryat70, jadivarlog
Run 2: [8..11] → digitechirchannel, whynationsfail2019, khateraaat, dw_farsi
Run 3: [0..3]  → back to the start
```

State is persisted to `state.json` after each run:
```json
{ "index": 4 }
```

---

## 🎯 Media Resolution Strategy

```
For each media URL in a feed item:
│
├─► 1. Bridge Manifest?
│       manifest["channel/msg_id"] exists AND file on disk?
│       ✓ Use raw.githubusercontent.com/<path>
│
├─► 2. Local Cache?
│       MD5(normalized_url) matches a filename in feeds/media/?
│       ✓ Use raw.githubusercontent.com/<cached_file>
│
├─► 3. CDN Live Download?
│       Content-Length ≤ 50 MB?
│       Not HTML error page?
│       Downloaded data > 512 bytes?
│       ✓ Save → use raw.githubusercontent.com/<new_file>
│
└─► 4. Fallback: keep original CDN URL (may not load in Iran)
```

---

## 🌐 Censorship Circumvention

This pipeline was built specifically for audiences in **Iran**, where Telegram CDN domains are blocked at the ISP level. The solution:

| Problem | Solution |
|---|---|
| CDN URLs expire in hours | Pre-download via MTProto before expiry |
| CDN domains blocked (Iran) | Replace with `raw.githubusercontent.com` |
| RSSHub rate limits | Multi-instance fallback + channel rotation |
| Large video files | Size gate + banner with tappable link |
| Text-only posts look broken | Placeholder thumbnail always injected |

GitHub's `raw.githubusercontent.com` domain is accessible from Iran without a VPN, making it an ideal permanent media host.

---

## 📰 RSS Feed Enrichment

Each processed feed XML includes:

```xml
<!-- Standard RSS 2.0 enclosure -->
<enclosure url="https://raw.githubusercontent.com/.../tg_iranintltv_12345.mp4"
           type="video/mp4"
           length="10000000" />

<!-- Yahoo Media RSS for Feeder Android / other readers -->
<media:content url="https://raw.githubusercontent.com/.../tg_iranintltv_12345.mp4"
               type="video/mp4"
               medium="video" />
```

And for video/audio/GIF posts, inside `<description><![CDATA[...]]>`:

```html
<a href="https://raw.githubusercontent.com/...mp4" style="...dark gradient banner...">
  ▶ MP4  Open Media | پخش رسانه
  برای پخش ضربه بزنید · Tap to open
</a>
```

---

## 🚀 Setup & Configuration

### Prerequisites

- A GitHub account with a repository (public or private)
- A Telegram account with API credentials from [my.telegram.org](https://my.telegram.org)
- Python 3.10+ installed locally (only needed for the one-time session generation)

---

### Step 1 — Fork & Clone

Fork this repository to your GitHub account, then clone it locally:

```bash
git clone https://github.com/your-username/your-repo.git
cd your-repo
```

---

### Step 2 — Get Telegram API Credentials

1. Go to [my.telegram.org/apps](https://my.telegram.org/apps) and log in with your Telegram account.
2. Create a new application (name and description can be anything).
3. Copy your **API ID** (a number) and **API Hash** (a string) — you'll need them in Step 4.

---

### Step 3 — Generate a Telethon StringSession

Install Telethon locally and run this one-time script:

```bash
pip install telethon
```

```python
from telethon.sync import TelegramClient
from telethon.sessions import StringSession

api_id   = 123456           # your API ID from my.telegram.org
api_hash = "your_api_hash"  # your API hash from my.telegram.org

with TelegramClient(StringSession(), api_id, api_hash) as client:
    print(client.session.save())
```

Running this will ask for your phone number and a verification code (standard Telegram login). After that it prints a long string — **copy it**. This is your `TELEGRAM_SESSION` secret. You only need to run this once.

---

### Step 4 — Configure GitHub Secrets

Go to your repository → **Settings → Secrets and variables → Actions → New repository secret** and add all three:

| Secret Name | What to paste |
|---|---|
| `TELEGRAM_API_ID` | The numeric API ID from Step 2 |
| `TELEGRAM_API_HASH` | The API hash string from Step 2 |
| `TELEGRAM_SESSION` | The long StringSession string from Step 3 |

---

### Step 5 — Add Your Placeholder Image

This is the image shown on text-only posts (posts with no photo or video). Place your image at:

```
feeds/media/default_img/text_placeholder.jpg
```

Then commit and push it:

```bash
git add feeds/media/default_img/text_placeholder.jpg
git commit -m "add: custom text placeholder image"
git push
```

> **Important:** Without this file, text-only posts will show a broken image. The pipeline will warn you in the Actions log if it's missing.

---

### Step 6 — Configure Your Channels

Edit the `CHANNELS` list in **both** of the following files to match the Telegram channels you want to mirror. Use the channel's username (the part after `t.me/`):

**`Fetch-feeds.sh`** — the full rotation pool (all channels):
```bash
CHANNELS=("channel1" "channel2" "channel3" "channel4" ...)
```

**`bridge.py`** — channels for MTProto media pre-fetching (keep in sync with above):
```python
CHANNELS = ["channel1", "channel2", "channel3", "channel4", ...]
```

You can also adjust how many channels are refreshed per run:
```bash
CHUNK_SIZE=4   # increase for faster refresh, at the cost of more Actions minutes
```

Commit and push your changes.

---

### Step 7 — Enable GitHub Actions Write Permission

Go to **Settings → Actions → General → Workflow permissions** and select **Read and write permissions**. Without this, the pipeline cannot commit the feed files back to the repository.

---

### Step 8 — Run the Pipeline

The workflow runs automatically **every 30 minutes**. To run it immediately:

1. Go to the **Actions** tab in your repository.
2. Click **Smart Telegram Content-Reader** in the left sidebar.
3. Click **Run workflow → Run workflow**.

After it completes, your feed files will be available at:
```
https://raw.githubusercontent.com/<your-username>/<your-repo>/main/feeds/<channel>.xml
```

---

### Step 9 — Subscribe in Your RSS Reader

Add the raw feed URLs to any RSS reader. Example for a channel called `iranintltv`:

```
https://raw.githubusercontent.com/your-username/your-repo/main/feeds/iranintltv.xml
```

Recommended readers with full media support:

| Reader | Platform | Notes |
|---|---|---|
| **Feeder** | Android | Best support for `<media:content>` |
| **Reeder 5** | iOS / macOS | Excellent media card rendering |
| **NetNewsWire** | iOS / macOS | Free and open source |
| **FreshRSS** | Self-hosted web | Supports enclosures and media RSS |
| **Miniflux** | Self-hosted web | Lightweight, great API |

---

## 🔑 Secrets Reference

| Secret | Required | Description |
|---|---|---|
| `TELEGRAM_API_ID` | ✅ Yes | Integer API ID from [my.telegram.org](https://my.telegram.org/apps) |
| `TELEGRAM_API_HASH` | ✅ Yes | String API hash from [my.telegram.org](https://my.telegram.org/apps) |
| `TELEGRAM_SESSION` | ✅ Yes | Telethon StringSession (run the generation script once locally) |

> **Note**: If any of the three secrets are absent, `bridge.py` exits silently as a no-op. The rest of the pipeline (RSSHub fetching + processing) continues normally. This makes the project safe to fork without secrets.

---

## ➕ Adding Channels

1. Add the channel slug to `CHANNELS` in `Fetch-feeds.sh`.
2. Add the same slug to `CHANNELS` in `bridge.py` (for MTProto media pre-fetching).
3. Optionally adjust `CHUNK_SIZE` in `Fetch-feeds.sh` if you want more channels refreshed per run.
4. Commit and push — the workflow will start including the new channel in the rotation automatically.

---

## 📁 File Structure

```
.
├── .github/
│   └── workflows/
│       └── fetch.yml              # GitHub Actions workflow definition
├── feeds/
│   ├── <channel>.xml              # Generated RSS feed per channel
│   └── media/
│       ├── manifest.json          # Bridge manifest (channel/id → path)
│       ├── default_img/
│       │   └── text_placeholder.jpg  # Fallback thumbnail for text posts
│       └── tg_<channel>_<id>.<ext>   # Committed media files
├── bridge.py                      # MTProto media pre-fetcher
├── Fetch-feeds.sh                 # Pipeline orchestrator & git pusher
├── process_feed.py                # RSS XML transformer & enricher
├── state.json                     # Channel rotation cursor
├── requirements.txt               # Python dependencies
└── README.md                      # This file
```

---

## 💾 Size & Storage Policy

| Limit | Value | Applies To |
|---|---|---|
| MTProto download limit | 50 MB per file | `bridge.py` |
| CDN fallback download limit | 50 MB per file | `process_feed.py` |
| GitHub single-file hard limit | 100 MB | GitHub platform |
| Image re-encoding quality | 70% JPEG | Static images only |
| Stale file pruning | > 48 hours + untracked | `Fetch-feeds.sh` maintenance |
| Messages fetched per channel | 10 most recent | `bridge.py` MTProto iteration |

---

## 📱 Compatibility

Tested and optimised for the following RSS readers:

| Reader | Platform | `<enclosure>` | `<media:content>` | Banner |
|---|---|---|---|---|
| **Feeder** | Android | ✅ | ✅ | ✅ |
| **Reeder 5** | iOS/macOS | ✅ | ✅ | ✅ |
| **NetNewsWire** | iOS/macOS | ✅ | ✅ | ✅ |
| **FreshRSS** | Web | ✅ | ✅ | ✅ |
| **Miniflux** | Web/Self-hosted | ✅ | ✅ | ✅ |
| Any WebView RSS reader | Any | ✅ | ✅ | ✅ |

---

## 📣 Release Description

> **Smart Telegram Content-Reader** is a fully automated, self-hosted GitHub Actions pipeline that converts Telegram public channels into permanent, censorship-resistant RSS feeds.
>
> It authenticates to Telegram via the official MTProto API (Telethon), pre-downloads all media — images, videos, audio, and GIFs — before ephemeral CDN URLs expire, commits them directly into the repository, and rewrites every feed's XML to serve permanent `raw.githubusercontent.com` links accessible without a VPN from anywhere in the world, including Iran.
>
> **Key capabilities:**
> - 🔐 MTProto-based Telegram authentication with zero persistent session files
> - 📦 Intelligent three-tier media resolution (manifest → local cache → live CDN)
> - 🔄 Smart channel rotation with state persistence across runs
> - 📡 Multi-instance RSSHub fallback for high availability
> - 🖼️ Automatic JPEG optimisation (70% quality, ~50-60% size reduction)
> - 📰 Full Media RSS enrichment (`<enclosure>` + `<media:content>`)
> - 🎬 Bilingual (English + Persian) styled media banners in feed descriptions
> - 🌐 Complete censorship circumvention — all media on raw.githubusercontent.com
> - 🧹 Automatic stale media pruning to keep repository size under control
> - 🛡️ Robust error handling — one bad channel never blocks the pipeline

---

## 🤝 Contributing

Contributions are welcome. Please open an issue to discuss major changes before submitting a pull request.

When adding a new channel, ensure it is added to **both** `CHANNELS` lists (in `Fetch-feeds.sh` and `bridge.py`).

---

<div align="center">

Built with ❤️ for free access to information.

</div>
