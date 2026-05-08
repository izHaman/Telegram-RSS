import os
import re
import base64
import xml.etree.ElementTree as ET
from PIL import Image

IMAGE_DIR = 'feeds/images'
FEED_DIR = 'feeds'
QUALITY = 60 # lower quality for base64 to keep xml small
MAX_WIDTH = 800 # smaller width for mobile feed

def get_base64(filepath):
    """convert image to base64 string"""
    with open(filepath, "rb") as f:
        return base64.b64encode(f.read()).decode('utf-8')

def process_feeds():
    """optimize images and embed them as base64 into xml"""
    if not os.path.exists(FEED_DIR): return

    for filename in os.listdir(FEED_DIR):
        if not filename.endswith('.xml'): continue
        filepath = os.path.join(FEED_DIR, filename)
        
        try:
            tree = ET.parse(filepath)
            root = tree.getroot()
            modified = False

            for item in root.findall('.//item'):
                desc_node = item.find('description')
                if desc_node is None or not desc_node.text: continue
                
                # find github raw links in description
                img_urls = re.findall(r'src="(https://raw\.githubusercontent\.com/[^"]+)"', desc_node.text)
                
                for url in img_urls:
                    img_name = url.split('/')[-1]
                    local_img = os.path.join(IMAGE_DIR, img_name)
                    
                    if os.path.exists(local_img):
                        # optimize image before encoding
                        with Image.open(local_img) as img:
                            if img.mode in ("RGBA", "P"): img = img.convert("RGB")
                            if img.width > MAX_WIDTH:
                                ratio = MAX_WIDTH / float(img.width)
                                img = img.resize((MAX_WIDTH, int(img.height * ratio)), Image.Resampling.LANCZOS)
                            img.save(local_img, "JPEG", optimize=True, quality=QUALITY)
                        
                        # convert to base64 and replace in xml
                        b64_data = get_base64(local_img)
                        desc_node.text = desc_node.text.replace(url, f"data:image/jpeg;base64,{b64_data}")
                        modified = True
            
            if modified:
                tree.write(filepath, encoding='utf-8', xml_declaration=True)
                print(f"successfully embedded images in {filename}")

        except Exception as e:
            print(f"error processing {filename}: {e}")

if __name__ == "__main__":
    process_feeds()
