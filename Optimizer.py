import os
from PIL import Image

IMAGE_DIR = 'feeds/images'
QUALITY = 70
MAX_WIDTH = 1080

def optimize_images():
    if not os.path.exists(IMAGE_DIR):
        return

    for filename in os.listdir(IMAGE_DIR):
        if filename.lower().endswith(('.jpg', '.jpeg', '.png')):
            filepath = os.path.join(IMAGE_DIR, filename)
            try:
                with Image.open(filepath) as img:
                    # Strip transparency layers to ensure safe JPEG encoding
                    if img.mode in ("RGBA", "P"):
                        img = img.convert("RGB")
                    
                    # Prevent oversized payloads; downscale while preserving aspect ratio
                    if img.width > MAX_WIDTH:
                        ratio = MAX_WIDTH / float(img.width)
                        new_height = int(float(img.height) * float(ratio))
                        img = img.resize((MAX_WIDTH, new_height), Image.Resampling.LANCZOS)
                    
                    img.save(filepath, "JPEG", optimize=True, quality=QUALITY)
            except Exception:
                pass # Silently skip corrupted assets to avoid breaking the CI pipeline

if __name__ == "__main__":
    optimize_images()
