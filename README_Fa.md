<div align="center">

<h1>📡 Smart Telegram Content-Reader</h1>

<p><em>یک پایپ‌لاین کاملاً خودکار بر بستر GitHub Actions که کانال‌های تلگرام را به فیدهای RSS دائمی و مقاوم در برابر سانسور تبدیل می‌کند — قابل دسترسی بدون VPN از هر نقطه‌ای از جهان.</em></p>

---

### 🌐 Language / زبان

[![English](https://img.shields.io/badge/README-English-blue?style=for-the-badge&logo=github)](./README.md) &nbsp;&nbsp; [![Farsi](https://img.shields.io/badge/README-Farsi-green?style=for-the-badge&logo=github)](#)

---

[![GitHub Actions](https://img.shields.io/badge/Automated-GitHub%20Actions-2088FF?style=flat-square&logo=github-actions&logoColor=white)](https://github.com/features/actions)
[![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB?style=flat-square&logo=python&logoColor=white)](https://www.python.org/)
[![Telegram MTProto](https://img.shields.io/badge/Telegram-MTProto%20API-26A5E4?style=flat-square&logo=telegram&logoColor=white)](https://core.telegram.org/mtproto)
[![RSSHub](https://img.shields.io/badge/RSSHub-Compatible-FF6600?style=flat-square)](https://rsshub.app/)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)](./LICENSE)

</div>

---

## 📋 فهرست مطالب

- [این پروژه چیست؟](#-این-پروژه-چیست)
- [چطور کار می‌کند؟](#-چطور-کار-میکند)
- [قابلیت‌ها](#-قابلیتها)
- [معماری کلی](#-معماری-کلی)
- [مراحل پایپ‌لاین](#-مراحل-پایپلاین)
- [سیستم چرخش کانال‌ها](#-سیستم-چرخش-کانالها)
- [استراتژی رفع آدرس رسانه](#-استراتژی-رفع-آدرس-رسانه)
- [دور زدن سانسور](#-دور-زدن-سانسور)
- [غنی‌سازی فید RSS](#-غنیسازی-فید-rss)
- [راه‌اندازی و پیکربندی](#-راهاندازی-و-پیکربندی)
- [راهنمای سیکرت‌ها](#-راهنمای-سیکرتها)
- [افزودن کانال جدید](#-افزودن-کانال-جدید)
- [ساختار فایل‌ها](#-ساختار-فایلها)
- [سیاست حجم و ذخیره‌سازی](#-سیاست-حجم-و-ذخیرهسازی)
- [سازگاری](#-سازگاری)

---

## 🔭 این پروژه چیست؟

**Smart Telegram Content-Reader** یک پل RSS بدون نیاز به زیرساخت خارجی است که کانال‌های عمومی تلگرام را به فیدهای RSS کاملاً خودمیزبان و دائمی تبدیل می‌کند — به‌طوری که تمام فایل‌های رسانه‌ای (تصویر، ویدیو، صدا، GIF) مستقیماً در ریپازیتوری ذخیره شده و از طریق آدرس‌های raw GitHub قابل دسترسی باشند.

**مشکل اصلی که حل می‌کند:** آدرس‌های CDN تلگرام **موقتی** هستند (ظرف چند ساعت منقضی می‌شوند) و در کشورهایی مانند **ایران** فیلتر هستند. فیدهای استاندارد RSSHub این لینک‌های کوتاه‌مدت CDN را در خود جا می‌دهند که رسانه‌ها را برای بخش بزرگی از مخاطبان غیرقابل دسترس می‌کند.

این پایپ‌لاین آن مشکل را کاملاً حل می‌کند:

1. احراز هویت به تلگرام از طریق API رسمی MTProto برای **پیش‌دانلود تمام رسانه‌ها** پیش از انقضای لینک‌های CDN.
2. ذخیره فایل‌ها در ریپازیتوری تا به **آدرس‌های دائمی `raw.githubusercontent.com`** تبدیل شوند که سانسور را دور می‌زنند.
3. بازنویسی XML هر فید به‌صورت خودکار تا خوانندگان لینک‌های پایدار و کارا ببینند — **بدون نیاز به VPN**.

---

## ⚙️ چطور کار می‌کند؟

```
┌─────────────────────────────────────────────────────┐
│              کران GitHub Actions                    │
│           (هر ۳۰ دقیقه، به‌صورت خودکار)             │
└──────────────────────┬──────────────────────────────┘
                       │
          ┌────────────▼────────────┐
          │   مرحله ۱: bridge.py    │  ← احراز هویت MTProto با Telethon
          │   پل رسانه‌ای تلگرام    │  ← دانلود تصویر، ویدیو،
          │                         │    صدا، GIF برای همه کانال‌ها
          └────────────┬────────────┘
                       │  manifest.json نوشته می‌شود
          ┌────────────▼────────────┐
          │  مرحله ۲: Fetch-feeds.sh│  ← چرخش بین کانال‌ها
          │  دریافت XML از RSSHub   │  ← ۴ کانال در هر اجرا
          │                         │  ← fallback چند instance
          └────────────┬────────────┘
                       │  XML خام RSSHub
          ┌────────────▼────────────┐
          │  مرحله ۳: process_feed  │  ← بازنویسی تمام آدرس‌های رسانه
          │  پردازشگر و غنی‌ساز فید │  ← تزریق تگ‌های enclosure
          │                         │  ← تزریق لینک رسانه
          └────────────┬────────────┘
                       │
          ┌────────────▼────────────┐
          │   git commit & push     │  ← آدرس‌های دائمی raw.githubusercontent.com
          │   feeds/<channel>.xml   │    اکنون در ریپازیتوری زنده هستند
          └─────────────────────────┘
```

---

## ✨ قابلیت‌ها

### 🔐 یکپارچه‌سازی با MTProto تلگرام
- احراز هویت به API رسمی تلگرام با استفاده از **Telethon** (پروتکل MTProto) — بدون اسکرپینگ یا اندپوینت‌های غیررسمی.
- دانلود **۱۰ پیام اخیر** به ازای هر کانال در هر اجرا.
- پشتیبانی از تمام انواع رسانه: **تصویر، ویدیو، فایل صوتی، GIF، و اسناد**.
- استفاده از `StringSession` سریال‌شده ذخیره‌شده به‌عنوان GitHub Secret — هیچ فایل `.session` روی دیسک runner نوشته نمی‌شود.

### 📦 کشینگ هوشمند رسانه و سیستم Manifest
- نگهداری یک `manifest.json` که هر جفت `channel/message_id` را به مسیر فایل محلی نگاشت می‌کند.
- **حذف تکراری**: فایل‌های قبلاً دانلود شده هرگز مجدداً دانلود نمی‌شوند — manifest پیش از هر فراخوانی شبکه بررسی می‌شود.
- **کش مبتنی بر محتوا**: فایل‌های اجراهای قبلی از طریق هش MD5 آدرس CDN پیدا می‌شوند.
- Manifest به‌صورت اتمیک (یک‌بار، پس از همه کانال‌ها) نوشته می‌شود تا از حالت‌های ناقص جلوگیری شود.

### 🔄 رفع آدرس رسانه با سه لایه اولویت
برای هر آدرس رسانه‌ای در یک آیتم فید، پردازشگر سه استراتژی را به ترتیب اولویت امتحان می‌کند:
1. **Manifest پل** — فایل پیش‌دانلود شده از MTProto (سریع‌ترین، بدون CDN)
2. **کش محلی** — فایل ذخیره‌شده در اجرای قبلی (جستجوی مبتنی بر هش)
3. **دانلود زنده CDN** — دانلود لحظه‌ای با کنترل حجم و تشخیص صفحات خطا

اگر هر سه روش شکست بخورند، آدرس CDN اصلی به‌عنوان آخرین راه‌حل حفظ می‌شود.

### 🌍 آدرس‌های مقاوم در برابر سانسور
- تمام رسانه‌های ذخیره‌شده از `raw.githubusercontent.com` سرو می‌شوند — بدون VPN در شبکه‌های سانسورشده (ایران و غیره) قابل دسترسی هستند.
- آدرس‌های CDN (دامنه‌های `cdn*.telegram-cdn.org` و `telesco.pe`) کاملاً در XML نهایی جایگزین می‌شوند.
- تصویر placeholder برای پست‌های متنی تزریق می‌شود تا کارت‌های فید هرگز خالی نباشند.

### 📡 Fallback چند Instance برای RSSHub
- برای هر کانال، **سه instance عمومی RSSHub** به ترتیب امتحان می‌شوند.
- در صورت برگشت پاسخ بدون رسانه یا پاسخ rate-limited از instance اصلی، به‌صورت خودکار به instance بعدی سوئیچ می‌شود.
- ابزار تشخیص: وجود `mp4`، `video`، یا `telesco.pe` در پاسخ بررسی می‌شود تا فید غنی از رسانه دریافت شده باشد.

### 🗂️ سیستم چرخش کانال
- یک **cursor در `state.json`** نگهداری می‌شود که در هر اجرا ۴ کانال جلو می‌رود.
- با ۱۲ کانال کل، هر کانال هر ۳ اجرا (~۹۰ دقیقه) به‌روز می‌شود.
- عملیات modulo cursor را به‌صورت ایمن wrap می‌کند — خطای index-out-of-bounds وجود ندارد.
- تازگی را در برابر استفاده از Actions و محدودیت‌های نرخ RSSHub متعادل می‌کند.

### 🖼️ بهینه‌سازی تصویر
- تصاویر JPEG/PNG دانلود شده با **کیفیت ۷۰%** از طریق Pillow دوباره encode می‌شوند.
- معمولاً حجم فایل را **۵۰ تا ۶۰ درصد** کاهش می‌دهد بدون artefact قابل مشاهده روی صفحه موبایل.
- تصاویر با کانال alpha به‌صورت ایمن به RGB تبدیل می‌شوند پیش از encode شدن به JPEG.
- GIF، ویدیو، و صدا بدون تغییر ذخیره می‌شوند (بدون re-encoding).

### 📰 غنی‌سازی فید RSS (Media RSS)
- تزریق عناصر `<enclosure>` (استاندارد RSS 2.0) برای هر پست دارای رسانه.
- تزریق عناصر `<media:content>` (Yahoo Media RSS) با attribute صحیح `medium` (`video` / `audio` / `image`).
- تزریق namespace `xmlns:media` روی root `<rss>` در صورتی که RSSHub آن را حذف کرده باشد.
- MIME type دقیق برای تمام فرمت‌های پشتیبانی‌شده (mp4, mkv, mov, webm, mp3, ogg, m4a, jpg, png, gif, webp).

### 🧹 پاک‌سازی خودکار رسانه‌ها
- فایل‌هایی که بیش از **۴۸ ساعت** قدیمی هستند و **توسط git ردیابی نشده‌اند** به‌صورت خودکار حذف می‌شوند.
- فایل‌های ردیابی‌شده توسط git (در آدرس‌های فید زنده) هرگز لمس نمی‌شوند.
- از رشد بی‌محدود دایرکتوری `feeds/media/` در طول اجراها جلوگیری می‌کند.

### 🛡️ مدیریت خطای مستحکم
- `set -euo pipefail` در shell script — هر خطای دست‌نخورده کل پایپ‌لاین را متوقف می‌کند.
- خطاهای مربوط به یک کانال (پاسخ خالی، شکست دانلود) به‌عنوان هشدار لاگ می‌شوند و رد می‌شوند — یک کانال بد هرگز بقیه را مسدود نمی‌کند.
- پل به‌عنوان **no-op بدون خطا** رفتار می‌کند وقتی secrets تلگرام غایب هستند (برای fork و PR ایمن است).
- اعتبارسنجی دانلود CDN: بررسی Content-Length قبل از دانلود، بررسی حداقل حجم، تشخیص صفحه خطای HTML.
- خطاهای بهینه‌سازی تصویر بلعیده می‌شوند — یک بهینه‌سازی ناموفق هرگز پایپ‌لاین را خراب نمی‌کند.

### 🔒 کنترل حجم و ذخیره‌سازی
- **محدودیت دانلود MTProto**: ۵۰ مگابایت به ازای هر فایل (پایین‌تر از محدودیت سخت ۱۰۰ مگابایتی GitHub).
- **محدودیت دانلود CDN fallback**: ۵۰ مگابایت جداگانه برای جلوگیری از اتمام دیسک روی runner‌های Actions.
- فایل‌های بزرگ با یک لاگ اطلاعاتی رد می‌شوند — آدرس CDN اصلی آنها به‌عنوان fallback حفظ می‌شود.

---

## 🏗️ معماری کلی

| مؤلفه | فایل | نقش |
|---|---|---|
| هماهنگ‌کننده Workflow | `fetch.yml` | trigger کران/dispatch در GitHub Actions |
| پل رسانه | `bridge.py` | احراز هویت MTProto، دانلود رسانه، manifest |
| نقطه ورود پایپ‌لاین | `Fetch-feeds.sh` | هماهنگی ۳ مرحله، git commit |
| پردازشگر فید | `process_feed.py` | بازنویسی URL، غنی‌سازی XML |
| وضعیت چرخش | `state.json` | cursor برای چرخش chunk کانال |
| وابستگی‌ها | `requirements.txt` | Pillow، Telethon |

---

## 🔬 مراحل پایپ‌لاین

### مرحله ۱ — `bridge.py`: پل رسانه‌ای تلگرام

**قبل** از هر دریافت RSSHub اجرا می‌شود. یک `TelegramClient` Telethon احراز هویت شده از طریق `StringSession` سریال‌شده باز می‌کند. برای هر کانال پیکربندی‌شده، ۱۰ پیام اخیر را بررسی می‌کند و هر رسانه‌ای که در manifest نیست را دانلود می‌کند.

**انواع رسانه پشتیبانی‌شده**: `image/jpeg`, `image/png`, `image/gif`, `image/webp`, `video/mp4`, `video/mkv`, `video/mov`, `video/webm`, `audio/mpeg`, `audio/ogg`, `audio/mp4`

**طرح نام‌گذاری**: `feeds/media/tg_<channel>_<message_id>.<ext>`

---

### مرحله ۲ — `Fetch-feeds.sh`: دریافت‌کننده RSSHub

cursor را از `state.json` می‌خواند، chunk 4 کاناله برای این اجرا را محاسبه می‌کند، و XML RSS هر کانال را از RSSHub با حلقه fallback چند instance دریافت می‌کند.

```bash
RSSHUB_INSTANCES=(
    "https://rsshub.rssforever.com"   # اولیه
    "https://rsshub.moeyy.cn"         # ثانویه
    "https://rsshub.app"              # رسمی (rate-limited)
)
```

---

### مرحله ۳ — `process_feed.py`: پردازشگر فید

XML خام را از stdin می‌خواند، هر `<item>` را پردازش می‌کند، XML غنی‌شده را به stdout می‌نویسد. تبدیل‌های کلیدی در هر آیتم:

- حذف تگ‌های قدیمی `<enclosure>` و `<media:content>`.
- استخراج permalink `t.me/<channel>/<id>` برای ساخت کلید جستجوی manifest.
- برای هر آدرس رسانه: امتحان manifest ← کش ← دانلود CDN.
- جایگزینی URL در body XML با آدرس raw GitHub دائمی.
- تزریق بنر دوزبانه برای رسانه‌های متحرک/صوتی.
- ساخت و الحاق تگ‌های `<enclosure>` + `<media:content>`.
- تزریق تصویر placeholder برای پست‌های متنی.

---

## 🔄 سیستم چرخش کانال‌ها

```
کانال‌ها (۱۲ کانال):
mamlekate | ircfspace | vahidonline | iranintltv | drtel | hatricktv
iholymaryat70 | jadivarlog | digitechirchannel | whynationsfail2019
khateraaat | dw_farsi

اجرای ۰: [0..3]  → mamlekate, ircfspace, vahidonline, iranintltv
اجرای ۱: [4..7]  → drtel, hatricktv, iholymaryat70, jadivarlog
اجرای ۲: [8..11] → digitechirchannel, whynationsfail2019, khateraaat, dw_farsi
اجرای ۳: [0..3]  → بازگشت به ابتدا
```

وضعیت بعد از هر اجرا در `state.json` ذخیره می‌شود:
```json
{ "index": 4 }
```

---

## 🎯 استراتژی رفع آدرس رسانه

```
برای هر آدرس رسانه در یک آیتم فید:
│
├─► ۱. Manifest پل؟
│       manifest["channel/msg_id"] وجود دارد و فایل روی دیسک هست؟
│       ✓ استفاده از raw.githubusercontent.com/<path>
│
├─► ۲. کش محلی؟
│       MD5(url_نرمال‌شده) با یک نام فایل در feeds/media/ مطابقت دارد؟
│       ✓ استفاده از raw.githubusercontent.com/<cached_file>
│
├─► ۳. دانلود زنده CDN؟
│       Content-Length ≤ ۵۰ مگابایت؟
│       صفحه خطای HTML نیست؟
│       داده دانلود شده > ۵۱۲ بایت؟
│       ✓ ذخیره → استفاده از raw.githubusercontent.com/<new_file>
│
└─► ۴. Fallback: نگه‌داری آدرس CDN اصلی (ممکن است در ایران لود نشود)
```

---

## 🌐 دور زدن سانسور

این پایپ‌لاین به‌طور خاص برای مخاطبان **ایران** ساخته شده است، جایی که دامنه‌های CDN تلگرام در سطح ISP مسدود شده‌اند. راه‌حل:

| مشکل | راه‌حل |
|---|---|
| آدرس‌های CDN ظرف چند ساعت منقضی می‌شوند | پیش‌دانلود از طریق MTProto قبل از انقضا |
| دامنه‌های CDN مسدود هستند (ایران) | جایگزینی با `raw.githubusercontent.com` |
| محدودیت نرخ RSSHub | Fallback چند instance + چرخش کانال |
| فایل‌های ویدیویی بزرگ | کنترل حجم + بنر با لینک قابل لمس |
| پست‌های متنی شکسته به نظر می‌رسند | placeholder thumbnail همیشه تزریق می‌شود |

دامنه `raw.githubusercontent.com` گیت‌هاب بدون VPN از ایران قابل دسترسی است و آن را به یک میزبان رسانه دائمی ایده‌آل تبدیل می‌کند.

---

## 📰 غنی‌سازی فید RSS

هر XML فید پردازش‌شده شامل موارد زیر است:

```xml
<!-- Enclosure استاندارد RSS 2.0 -->
<enclosure url="https://raw.githubusercontent.com/.../tg_iranintltv_12345.mp4"
           type="video/mp4"
           length="10000000" />

<!-- Yahoo Media RSS برای Feeder Android و سایر خوانندگان -->
<media:content url="https://raw.githubusercontent.com/.../tg_iranintltv_12345.mp4"
               type="video/mp4"
               medium="video" />
```

و برای پست‌های ویدیو/صدا/GIF، درون `<description><![CDATA[...]]>`:

```html
<a href="https://raw.githubusercontent.com/...mp4" style="...بنر گرادیانت تیره...">
  ▶ MP4  Open Media | پخش رسانه
  برای پخش ضربه بزنید · Tap to open
</a>
```

---

## 🚀 راه‌اندازی و پیکربندی

### پیش‌نیازها

- یک حساب GitHub با ریپازیتوری (عمومی یا خصوصی)
- یک حساب تلگرام با اعتبارنامه API از [my.telegram.org](https://my.telegram.org)
- Python 3.10+ نصب‌شده روی سیستم محلی (فقط برای یک‌بار تولید session)
- -- **نکته:** اگر به API تلگرام دسترسی ندارید، مراحل ۲ تا ۴ را نادیده بگیرید. (در این صورت فقط به عکس و متن ها دسترسی دارید)

---

### مرحله ۱ — Fork و Clone

این ریپازیتوری را fork کنید، یا به‌صورت محلی clone کنید:

```bash
git clone https://github.com/username-شما/repo-شما.git
cd repo-شما
```

---

### مرحله ۲ — دریافت اعتبارنامه‌های API تلگرام

1. به [my.telegram.org/apps](https://my.telegram.org/apps) بروید و با حساب تلگرام خود وارد شوید.
2. یک اپلیکیشن جدید بسازید (نام و توضیحات هر چیزی می‌تواند باشد).
3. **API ID** (عدد) و **API Hash** (رشته) خود را کپی کنید — در مرحله ۴ به آن‌ها نیاز دارید.

---

### مرحله ۳ — تولید Telethon StringSession

Telethon را نصب کنید و این اسکریپت یک‌باره را اجرا کنید:

```bash
pip install telethon
```

```python
from telethon.sync import TelegramClient
from telethon.sessions import StringSession

api_id   = 123456           # API ID از my.telegram.org
api_hash = "your_api_hash"  # API hash از my.telegram.org

with TelegramClient(StringSession(), api_id, api_hash) as client:
    print(client.session.save())
```

این اسکریپت شماره تلفن و کد تأیید می‌خواهد (ورود استاندارد تلگرام). بعد یک رشته بلند چاپ می‌کند — **آن را کپی کنید**. این همان secret `TELEGRAM_SESSION` شماست. فقط یک‌بار باید این کار را بکنید.

---

### مرحله ۴ — پیکربندی GitHub Secrets

به ریپازیتوری خود بروید ← **Settings → Secrets and variables → Actions → New repository secret** و هر سه را اضافه کنید:

| نام Secret | چه چیزی را paste کنید |
|---|---|
| `TELEGRAM_API_ID` | API ID عددی از مرحله ۲ |
| `TELEGRAM_API_HASH` | رشته API hash از مرحله ۲ |
| `TELEGRAM_SESSION` | رشته بلند StringSession از مرحله ۳ |

---

### مرحله ۵ — افزودن عکس Placeholder

این عکسی است که برای پست‌های متنی (پست‌هایی بدون عکس یا ویدیو) نمایش داده می‌شود. عکس خود را در این مسیر قرار دهید:

```
feeds/media/default_img/text_placeholder.jpg
```

سپس commit و push کنید:

```bash
git add feeds/media/default_img/text_placeholder.jpg
git commit -m "add: custom text placeholder image"
git push
```

> **مهم:** بدون این فایل، پست‌های متنی عکس شکسته نشان می‌دهند. پایپ‌لاین در صورت نبود این فایل در لاگ Actions هشدار می‌دهد.

---

### مرحله ۶ — پیکربندی کانال‌ها

لیست `CHANNELS` را در **هر دو** فایل زیر ویرایش کنید. از نام کاربری کانال استفاده کنید (بخشی که بعد از `t.me/` می‌آید):

**`Fetch-feeds.sh`** — pool چرخش کامل (همه کانال‌ها):
```bash
CHANNELS=("channel1" "channel2" "channel3" "channel4" ...)
```

**`bridge.py`** — کانال‌ها برای پیش‌دانلود MTProto (باید با بالا همگام باشد):
```python
CHANNELS = ["channel1", "channel2", "channel3", "channel4", ...]
```

همچنین می‌توانید تعداد کانال‌های به‌روزشده در هر اجرا را تنظیم کنید:
```bash
CHUNK_SIZE=4   # برای refresh سریع‌تر افزایش دهید، با هزینه بیشتر Actions minutes
```

تغییرات را commit و push کنید.

---

### مرحله ۷ — فعال‌سازی دسترسی نوشتن Actions

به **Settings → Actions → General → Workflow permissions** بروید و **Read and write permissions** را انتخاب کنید. بدون این، پایپ‌لاین نمی‌تواند فایل‌های فید را در ریپازیتوری commit کند.

---

### مرحله ۸ — اجرای پایپ‌لاین

Workflow به‌صورت خودکار **هر ۳۰ دقیقه** اجرا می‌شود. برای اجرای فوری:

1. به تب **Actions** در ریپازیتوری خود بروید.
2. روی **Smart Telegram Content-Reader** در نوار کناری کلیک کنید.
3. روی **Run workflow → Run workflow** کلیک کنید.

بعد از اتمام، فایل‌های فید شما در این آدرس در دسترس خواهند بود:
```
https://raw.githubusercontent.com/<username-شما>/<repo-شما>/main/feeds/<channel>.xml
```

---

### مرحله ۹ — عضویت در RSS Reader

آدرس‌های فید raw را به هر خواننده RSS اضافه کنید. مثال برای کانال `iranintltv`:

```
https://raw.githubusercontent.com/username-شما/repo-شما/main/feeds/iranintltv.xml
```

خوانندگان پیشنهادی با پشتیبانی کامل از رسانه:

| خواننده | پلتفرم | توضیحات |
|---|---|---|
| **Feeder** | Android | بهترین پشتیبانی از `<media:content>` |
| **Reeder 5** | iOS / macOS | رندر عالی کارت رسانه |
| **NetNewsWire** | iOS / macOS | رایگان و متن‌باز |
| **FreshRSS** | Web self-hosted | پشتیبانی از enclosure و Media RSS |
| **Miniflux** | Web self-hosted | سبک، با API عالی |

---

## 🔑 راهنمای سیکرت‌ها

| Secret | الزامی | توضیح |
|---|---|---|
| `TELEGRAM_API_ID` | ✅ بله | شناسه API عددی از [my.telegram.org](https://my.telegram.org/apps) |
| `TELEGRAM_API_HASH` | ✅ بله | API hash از [my.telegram.org](https://my.telegram.org/apps) |
| `TELEGRAM_SESSION` | ✅ بله | Telethon StringSession (یک‌بار اسکریپت تولید را اجرا کنید) |

> **نکته**: اگر هر یک از سه secret غایب باشد، `bridge.py` به‌صورت بی‌صدا به‌عنوان no-op خارج می‌شود. بقیه پایپ‌لاین (دریافت RSSHub + پردازش) به‌طور عادی ادامه می‌یابد. این پروژه را برای fork کردن بدون secret ایمن می‌کند.

---

## ➕ افزودن کانال جدید

1. slug کانال را به `CHANNELS` در `Fetch-feeds.sh` اضافه کنید.
2. همان slug را به `CHANNELS` در `bridge.py` اضافه کنید (برای پیش‌دانلود رسانه از MTProto).
3. اختیاری: `CHUNK_SIZE` در `Fetch-feeds.sh` را تنظیم کنید اگر می‌خواهید کانال‌های بیشتری در هر اجرا به‌روز شوند.
4. commit کنید و push کنید — workflow به‌صورت خودکار کانال جدید را در چرخش شامل می‌کند.

---

## 📁 ساختار فایل‌ها

```
.
├── .github/
│   └── workflows/
│       └── fetch.yml                  # تعریف workflow در GitHub Actions
├── feeds/
│   ├── <channel>.xml                  # فید RSS تولیدشده به ازای هر کانال
│   └── media/
│       ├── manifest.json              # manifest پل (channel/id → path)
│       ├── default_img/
│       │   └── text_placeholder.jpg   # thumbnail جایگزین برای پست‌های متنی
│       └── tg_<channel>_<id>.<ext>    # فایل‌های رسانه ذخیره‌شده
├── bridge.py                          # پیش‌دانلودکننده رسانه از MTProto
├── Fetch-feeds.sh                     # هماهنگ‌کننده پایپ‌لاین و pusher گیت
├── process_feed.py                    # تبدیل‌کننده و غنی‌ساز XML RSS
├── state.json                         # cursor چرخش کانال
├── requirements.txt                   # وابستگی‌های Python
└── README.md                          # فایل انگلیسی
```

---

## 💾 سیاست حجم و ذخیره‌سازی

| محدودیت | مقدار | اعمال‌شده به |
|---|---|---|
| محدودیت دانلود MTProto | ۵۰ مگابایت به ازای هر فایل | `bridge.py` |
| محدودیت دانلود CDN fallback | ۵۰ مگابایت به ازای هر فایل | `process_feed.py` |
| محدودیت سخت فایل در GitHub | ۱۰۰ مگابایت | پلتفرم GitHub |
| کیفیت re-encoding تصویر | ۷۰% JPEG | فقط تصاویر استاتیک |
| پاک‌سازی فایل‌های قدیمی | > ۴۸ ساعت + ردیابی‌نشده | نگهداری `Fetch-feeds.sh` |
| پیام‌های دریافتی به ازای کانال | ۱۰ پیام اخیر | MTProto `bridge.py` |

---

## 📱 سازگاری

تست و بهینه‌سازی‌شده برای خوانندگان RSS زیر:

| خواننده | پلتفرم | `<enclosure>` | `<media:content>` | بنر |
|---|---|---|---|---|
| **Feeder** | Android | ✅ | ✅ | ✅ |
| **Reeder 5** | iOS/macOS | ✅ | ✅ | ✅ |
| **NetNewsWire** | iOS/macOS | ✅ | ✅ | ✅ |
| **FreshRSS** | Web | ✅ | ✅ | ✅ |
| **Miniflux** | Web/Self-hosted | ✅ | ✅ | ✅ |
| هر خواننده RSS مبتنی بر WebView | هر پلتفرم | ✅ | ✅ | ✅ |

---

<div align="center">

ساخته شده با 🩵 برای دسترسی آزاد به اطلاعات.

</div>
