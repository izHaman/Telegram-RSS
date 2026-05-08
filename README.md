# 🚀 Smart Telegram Content-Reader (STC-Reader)
> A high-performance, automated RSS proxy and media-mirroring bridge for restricted network environments.

---

<p align="center">
  <a href="#-farsi-documentation">فارسی</a> • 
  <a href="#-english-documentation">English</a>
</p>

---

## 🇮🇷 Farsi Documentation

### معرفی STC-Reader
**STC-Reader** ( Smart Telegram Content-Reader) یک راهکار پیشرفته برای دسترسی به محتوای کانال‌های تلگرامی در قالب RSS است، به‌طوری که تمام محدودیت‌های شبکه‌ای و فیلترینگ رسانه‌ها (تصاویر و ویدیوها) را دور می‌زند. این ابزار با استفاده از **GitHub Actions** و یک معماری هوشمند، محتوا را از پل‌های RSS دریافت کرده و تمام دارایی‌های رسانه‌ای را روی دامنه‌ی اصلی گیت‌هاب آینه‌سازی (Mirror) می‌کند.

### ویژگی‌های کلیدی
* **Media Proxying:** جایگزینی خودکار لینک‌های فیلترشده تلگرام با لینک‌های مستقیم دامنه‌ی اصلی گیت‌هاب.
* **Image Optimization:** کاهش حجم هوشمند تصاویر با استفاده از پایتون (Pillow) برای افزایش سرعت لود در موبایل.
* **Anti-Rate-Limit Logic:** سیستم پردازش دسته‌ای (Chunking) با تاخیرهای تصادفی (Random Sleep) برای جلوگیری از مسدود شدن توسط سرورهای RSSHub.
* **Zero-Maintenance:** کاملاً خودکار؛ حذف خودکار تصاویر قدیمی (بیش از ۳ روز) برای مدیریت فضای مخزن.
* **High Availability:** استفاده از دامنه‌ی اصلی `github.com/raw` برای تضمین پایداری در شبکه‌های تحت محدودیت (Whitelist).

### نحوه راه‌اندازی
۱. ریپازیتوری را **Fork** کنید.
۲. در بخش **Settings > Actions > General**، دسترسی **Read and Write permissions** را فعال کنید.
۳. فایل `Fetch-feeds.sh` را باز کرده و لیست `CHANNELS` را طبق نیاز خود ویرایش کنید.
۴. اکشن به صورت خودکار هر ۳۰ دقیقه اجرا می‌شود، اما می‌توانید به صورت دستی از تب **Actions** آن را `Run` کنید.

### استفاده در فیدخوان (Feeder)
برای اضافه کردن فیدها به اپلیکیشن خود، از الگوی زیر استفاده کنید:
`https://github.com/USER_NAME/STC-Reader/raw/main/feeds/CHANNEL_NAME.xml`

### نکته
• به دلیل محدودیت های Rsshub و Github، آپدیت شدن feed ها ممکن است با کمی تأخیر انجام شود.

• تعداد چنل ها مستقیماً روی زمان آپدیت شدن فید ها تاثیر میگذارد (سیستم نوبتی)

---

## 🇬🇧 English Documentation

### Overview
**STC-Reader** is an automated pipeline designed to bridge Telegram's content to RSS readers while overcoming network censorship and media filtering. By leveraging **GitHub Actions**, it fetches RSS feeds, downloads filtered media assets, and mirrors them directly onto GitHub's main domain for seamless accessibility.

### Key Features
* **Deep Asset Mirroring:** Automatically detects and proxies filtered Telegram links (`telesco.pe`) to GitHub's raw domain.
* **Smart Image Optimization:** Utilizes a Python-based engine (`Pillow`) to compress assets, ensuring fast load times on mobile devices.
* **Anti-Throttling Architecture:** Implements chunk-based processing with randomized human-like delays to bypass RSSHub rate limits.
* **Auto-Maintenance:** Built-in cleanup logic that purges assets older than 3 days to keep the repository slim and efficient.
* **Bypass Filtering:** Optimized for regions with strict internet filtering by utilizing the `github.com` whitelist.

### Technical Stack
| Component | Technology |
| :--- | :--- |
| **Automation** | GitHub Actions (YAML) |
| **Core Scripting** | Bash (Shell) |
| **Optimization** | Python 3.x (Pillow Library) |
| **Content Source** | RSSHub Bridge |

### Setup Instructions
1.  **Fork** this repository.
2.  Navigate to **Settings > Actions > General** and ensure **Workflow permissions** are set to **Read and Write**.
3.  Customize the `CHANNELS` array in `Fetch-feeds.sh` with your desired Telegram handles.
4.  The workflow is pre-configured to run every 30 minutes, or you can trigger it manually via the **Actions** tab.

### Usage in RSS Readers
Add your feeds to any RSS client (like Feeder or Tiny Tiny RSS) using the following URL pattern:
`https://github.com/[YOUR_USERNAME]/STC-Reader/raw/main/feeds/[CHANNEL_ID].xml`

---

## 🛠 Project Structure
```text
STC-Reader/
├── .github/workflows/
│   └── sync.yml           # Automation logic & schedule
├── feeds/
│   ├── images/            # Mirrored & Optimized media assets
│   └── channel_name.xml   # Final proxied RSS feeds
├── Fetch-feeds.sh         # Core shell logic & anti-rate-limit
├── optimizer.py           # Python image processing engine
└── state.json             # Persistence for chunked sync
```
### Notes
• Due to RSSHub and GitHub limitations, feed updates may be slightly delayed.
• The number of channels directly affects the feed update interval (round-robin system).
