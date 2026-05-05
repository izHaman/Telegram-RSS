import os
import sys
from PIL import Image

IMAGE_DIR = "feeds/images"
QUALITY = 80
MAX_WIDTH = 1080

def process_assets():
    if not os.path.exists(IMAGE_DIR):
        return

    for filename in os.listdir(IMAGE_DIR):
        if filename.lower().endswith(('.jpg', '.jpeg', '.png')):
            path = os.path.join(IMAGE_DIR, filename)
            try:
                if os.path.getsize(path) == 0:
                    os.remove(path)
                    continue

                with Image.open(path) as img:
                    # Maintenance: Standardize format
                    if img.mode in ("RGBA", "P"):
                        img = img.convert("RGB")
                    
                    # Resize for mobile efficiency
                    if img.width > MAX_WIDTH:
                        ratio = MAX_WIDTH / float(img.width)
                        new_height = int(float(img.height) * float(ratio))
                        img = img.resize((MAX_WIDTH, new_height), Image.Resampling.LANCZOS)
                    
                    img.save(path, "JPEG", quality=QUALITY, optimize=True)
            except Exception:
                continue

if __name__ == "__main__":
    process_assets()
    sys.exit(0)
