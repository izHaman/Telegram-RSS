#!/usr/bin/env python3
import os
import xml.etree.ElementTree as ET
from datetime import datetime

FEEDS_DIR = "feeds"

def parse_date(date_str):
    if not date_str:
        return "Unknown"
    try:
        for fmt in ["%a, %d %b %Y %H:%M:%S %z", "%a, %d %b %Y %H:%M:%S %Z"]:
            try:
                dt = datetime.strptime(date_str, fmt)
                return dt.strftime("%Y-%m-%d %H:%M")
            except:
                continue
        return date_str[:16]
    except:
        return date_str[:16]

def check_feed(xml_path):
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        channel = root.find("channel")
        if channel is None:
            return None
        title = channel.findtext("title", "Untitled").replace("Telegram Channel: @", "")
        last_build = channel.findtext("lastBuildDate", "")
        items = len(channel.findall("item"))
        direct_media = 0
        for item in channel.findall("item"):
            enc = item.find("enclosure")
            if enc is not None and "api.telegram.org" in enc.get("url", ""):
                direct_media += 1
        return {
            "title": title,
            "last_build": parse_date(last_build),
            "items": items,
            "direct_media": direct_media
        }
    except Exception as e:
        return None

def main():
    if not os.path.isdir(FEEDS_DIR):
        print(f"No feeds directory found.")
        return
    xml_files = sorted([f for f in os.listdir(FEEDS_DIR) if f.endswith(".xml")])
    if not xml_files:
        print(f"No XML files found.")
        return
    print("\n" + "="*60)
    print("📊 FEED STATUS REPORT")
    print("="*60)
    print(f"{'Channel':<20} {'Last Update':<18} {'Items':<6} {'Direct Media':<12}")
    print("-"*60)
    for filename in xml_files:
        path = os.path.join(FEEDS_DIR, filename)
        info = check_feed(path)
        if info:
            print(f"{info['title']:<20} {info['last_build']:<18} {info['items']:<6} {info['direct_media']:<12}")
        else:
            print(f"{filename:<20} {'ERROR':<18} {'-':<6} {'-':<12}")
    print("="*60)

if __name__ == "__main__":
    main()
