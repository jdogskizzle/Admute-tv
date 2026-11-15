"""Draws the app icon (three parallax layers) and the Top Shelf images into the asset
catalog. A placeholder design: a TV with a muted speaker. Swap the PNGs for your own art,
or change the drawing here and run:  python3 tools/make_icons.py   (needs Pillow)."""

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent / "AdmuteTV" / "Assets.xcassets"
BRAND = ROOT / "App Icon & Top Shelf Image.brandassets"
ACCENT = (224, 120, 92)
INFO = {"author": "xcode", "version": 1}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def write(path, data):
    path.mkdir(parents=True, exist_ok=True)
    (path / "Contents.json").write_text(json.dumps(data, indent=2) + "\n")


def gradient(w, h, top, bottom):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def back(w, h):
    img = gradient(w, h, (44, 30, 34), (14, 14, 20))
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse([w * 0.15, h * 0.05, w * 0.85, h * 1.1], fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(h * 0.18))
    return Image.composite(Image.new("RGB", (w, h), ACCENT), img, glow.point(lambda v: v * 0.45)).convert("RGBA")


def middle(w, h):
    """A TV screen outline."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = h / 240
    box = [w / 2 - 125 * s, h / 2 - 78 * s, w / 2 + 125 * s, h / 2 + 70 * s]
    d.rounded_rectangle(box, radius=18 * s, fill=(255, 255, 255, 28), outline=(255, 255, 255, 200), width=round(7 * s))
    d.rounded_rectangle([w / 2 - 40 * s, h / 2 + 80 * s, w / 2 + 40 * s, h / 2 + 88 * s], radius=4 * s, fill=(255, 255, 255, 170))
    return img


def speaker(d, cx, cy, s, colour, slash=True):
    """A speaker with a slash through it, centred on (cx, cy), about 100*s wide."""
    d.rectangle([cx - 46 * s, cy - 16 * s, cx - 22 * s, cy + 16 * s], fill=colour)
    d.polygon([(cx - 24 * s, cy - 16 * s), (cx + 8 * s, cy - 44 * s), (cx + 8 * s, cy + 44 * s), (cx - 24 * s, cy + 16 * s)], fill=colour)
    if slash:
        d.line([(cx + 20 * s, cy - 22 * s), (cx + 56 * s, cy + 22 * s)], fill=colour, width=round(11 * s))
        d.line([(cx + 56 * s, cy - 22 * s), (cx + 20 * s, cy + 22 * s)], fill=colour, width=round(11 * s))


def front(w, h):
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    speaker(ImageDraw.Draw(img), w / 2 - 4 * h / 240, h / 2 - 4 * h / 240, h / 240 * 1.05, ACCENT + (255,))
    return img


def top_shelf(w, h):
    img = back(w, h)
    d = ImageDraw.Draw(img)
    s = h / 720
    speaker(d, w / 2 - 330 * s, h / 2, 2.2 * s, ACCENT + (255,))
    big = ImageFont.truetype(FONT, round(150 * s))
    small = ImageFont.truetype(FONT.replace("-Bold", ""), round(48 * s))
    d.text((w / 2 - 170 * s, h / 2 - 20 * s), "admute", font=big, fill=(255, 255, 255), anchor="ls")
    d.text((w / 2 - 164 * s, h / 2 + 70 * s), "Live TV, ads muted", font=small, fill=(255, 255, 255, 170), anchor="ls")
    return img.convert("RGB")


def stack(name, size, scales):
    w, h = size
    path = BRAND / f"{name}.imagestack"
    write(path, {"info": INFO, "layers": [{"filename": f"{l}.imagestacklayer"} for l in ("Front", "Middle", "Back")]})
    for layer, draw in (("Front", front), ("Middle", middle), ("Back", back)):
        lp = path / f"{layer}.imagestacklayer"
        write(lp, {"info": INFO})
        images = []
        for sc in scales:
            f = f"{layer.lower()}{'' if sc == 1 else f'@{sc}x'}.png"
            img = draw(w * sc, h * sc)
            (lp / "Content.imageset").mkdir(parents=True, exist_ok=True)
            (img.convert("RGB") if layer == "Back" else img).save(lp / "Content.imageset" / f)   # the back layer must be opaque
            images.append({"filename": f, "idiom": "tv", "scale": f"{sc}x"})
        write(lp / "Content.imageset", {"images": images, "info": INFO})


def shelf(name, size):
    w, h = size
    path = BRAND / f"{name}.imageset"
    path.mkdir(parents=True, exist_ok=True)
    images = []
    for sc in (1, 2):
        f = f"{name.lower().replace(' ', '-')}{'' if sc == 1 else '@2x'}.png"
        top_shelf(w * sc, h * sc).save(path / f)
        images.append({"filename": f, "idiom": "tv", "scale": f"{sc}x"})
    write(path, {"images": images, "info": INFO})


write(ROOT, {"info": INFO})
write(BRAND, {"assets": [
    {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
    {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
    {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
    {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
], "info": INFO})
stack("App Icon", (400, 240), (1, 2))
stack("App Icon - App Store", (1280, 768), (1,))
shelf("Top Shelf Image", (1920, 720))
shelf("Top Shelf Image Wide", (2320, 720))
print("icons written to", BRAND)
