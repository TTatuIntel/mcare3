"""One-off launcher-icon generator (fallback for flutter_launcher_icons).

Regenerates Android mipmaps, web PWA icons + favicon, and the iOS AppIcon set
from assets/branding/app_icon.png. iOS icons are flattened onto the brand colour
because the App Store rejects icons with an alpha channel.

Run from the frontend dir:  python scripts/gen_icons.py
"""

import os
import re

from PIL import Image

FRONTEND = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SRC = os.path.join(FRONTEND, "assets", "branding", "app_icon.png")
BRAND = (0x63, 0x66, 0xF1, 255)  # #6366F1

src = Image.open(SRC).convert("RGBA")


def resized(size):
    return src.resize((size, size), Image.LANCZOS)


def flatten(img, bg=BRAND):
    base = Image.new("RGBA", img.size, bg)
    base.alpha_composite(img)
    return base.convert("RGB")


def save(img, *parts):
    path = os.path.join(FRONTEND, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("wrote", os.path.relpath(path, FRONTEND))


# --- Android legacy mipmaps (alpha allowed) --------------------------------
android = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
for folder, size in android.items():
    save(resized(size), "android", "app", "src", "main", "res", folder, "ic_launcher.png")

# --- Web PWA icons ----------------------------------------------------------
save(resized(192), "web", "icons", "Icon-192.png")
save(resized(512), "web", "icons", "Icon-512.png")
save(flatten(resized(192)), "web", "icons", "Icon-maskable-192.png")
save(flatten(resized(512)), "web", "icons", "Icon-maskable-512.png")
save(resized(32), "web", "favicon.png")

# --- iOS AppIcon set (must be opaque, no alpha) -----------------------------
ios_dir = os.path.join(FRONTEND, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
name_re = re.compile(r"Icon-App-([\d.]+)x[\d.]+@(\d)x\.png")
if os.path.isdir(ios_dir):
    for fn in os.listdir(ios_dir):
        m = name_re.match(fn)
        if not m:
            continue
        px = round(float(m.group(1)) * int(m.group(2)))
        flatten(resized(px)).save(os.path.join(ios_dir, fn))
        print("wrote", os.path.relpath(os.path.join(ios_dir, fn), FRONTEND))

print("DONE icons")
