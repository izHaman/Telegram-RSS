import os
import re
import hashlib
import xml.etree.ElementTree as ET
from PIL import Image

# settings
IMAGE_DIR = 'feeds/images'
FEED_DIR = 'feeds'
QUALITY = 70
MAX_WIDTH = 1080

def optimize_images():
    """compress and resize images to save space and bandwidth"""
    if not os.path.exists(IMAGE_DIR):
        return

    for filename in os.listdir(IMAGE_DIR):
        if filename.lower().endswith(('.jpg', '.jpeg', '.png')):
            filepath = os.path.join(IMAGE_DIR, filename)
            try:
                with Image.open(filepath) as img:
                    # convert to rgb if necessary
                    if img.mode in ("RGBA", "P"):
                        img = img.convert("RGB")
                    
                    # resize if too large
                    if img.width > MAX_WIDTH:
                        ratio = MAX_WIDTH / float(img.width)
                        new_height = int(float(img.height) * float(ratio))
                        img = img.resize((MAX_WIDTH, new_height), Image.Resampling.LANCZOS)
                    
                    # save with optimization
                    img.save(filepath, "JPEG", optimize=True, quality=QUALITY)
            except Exception as e:
                print(f"skipping {filename}: {e}")

def patch_rss_feeds():
    """inject enclosure tags for better app compatibility"""
    if not os.path.exists(FEED_DIR):
        return

    for filename in os.listdir(FEED_DIR):
        if filename.endswith('.xml'):
            filepath = os.path.join(FEED_DIR, filename)
            try:
                # register namespaces to avoid 'ns0' prefixes
                ET.register_namespace('content', "http://purl.org/rss/1.0/modules/content/")
                ET.register_namespace('dc', "http://purl.org/dc/elements/1.1/")
                
                tree = ET.parse(filepath)
                root = tree.getroot()
                
                for item in root.findall('.//item'):
                    description_node = item.find('description')
                    if description_node is None or not description_node.text:
                        continue
                    
                    content = description_node.text
                    # look for our proxied images (statically or direct github)
                    img_match = re.search(r'src="([^"]*(?:statically\.io|github\.com)[^"]*)"', content)
                    
                    if img_match:
                        img_url = img_match.group(1)
                        # add enclosure if not present
                        if item.find('enclosure') is None:
                            enclosure = ET.SubElement(item, 'enclosure')
                            enclosure.set('url', img_url)
                            enclosure.set('type', 'image/jpeg')
                            enclosure.set('length', '0')
                
                tree.write(filepath, encoding='utf-8', xml_declaration=True)
                print(f"patched {filename}")
                
            except Exception as e:
                print(f"failed to patch {filename}: {e}")

if __name__ == "__main__":
    print("starting image optimization...")
    optimize_images()
    print("starting rss structural patching...")
    patch_rss_feeds()
    print("done.")

