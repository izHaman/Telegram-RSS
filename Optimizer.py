import os
from PIL import Image

# Configuration
IMAGE_DIR = "feeds/images"
QUALITY = 80  # Target compression quality
MAX_WIDTH = 1200 # Max width to reduce file size further

def process_images():
    if not os.path.exists(IMAGE_DIR):
        return

    for filename in os.listdir(IMAGE_DIR):
        if filename.lower().endswith(('.jpg', '.jpeg', '.png')):
            file_path = os.path.join(IMAGE_DIR, filename)
            
            try:
                with Image.open(file_path) as img:
                    # Remove metadata and convert to RGB
                    if img.mode in ("RGBA", "P"):
                        img = img.convert("RGB")
                    
                    # Resize if too large
                    if img.width > MAX_WIDTH:
                        ratio = MAX_WIDTH / float(img.width)
                        new_height = int(float(img.height) * float(ratio))
                        img = img.resize((MAX_WIDTH, new_height), Image.Resampling.LANCZOS)
                    
                    # Overwrite with optimized version
                    img.save(file_path, "JPEG", quality=QUALITY, optimize=True)
                    print(f"  [Optimizer] Compressed: {filename}")
            except Exception as e:
                print(f"  [Optimizer] Skip {filename}: {e}")

if __name__ == "__main__":
    process_images()

