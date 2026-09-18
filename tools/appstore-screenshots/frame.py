#!/usr/bin/env python3
"""Frames each raw capture on the brand wash with its App Store caption.

Outputs 1284 x 2778 PNGs — App Store Connect's 6.5" slot, the size the raw
captures already are, so the device art is never resampled up.

    python3 tools/appstore-screenshots/frame.py
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os

HERE = os.path.dirname(os.path.abspath(__file__))
RAW  = os.path.join(HERE, "raw_zh")
OUT  = os.path.join(HERE, "zh-Hant")
os.makedirs(OUT, exist_ok=True)

W, H = 1284, 2778
FONT = "/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc"
SEMI, REG = 10, 2                      # PingFang TC Semibold / Regular

BRAND_TOP    = (0x8E, 0x26, 0x22)      # Theme.Palette.brand
BRAND_BOTTOM = (0x5C, 0x15, 0x13)

MARGIN   = 96
HEAD_Y   = 176
HEAD_PX  = 86
SUB_PX   = 42
SHOT_W   = 980
SHOT_TOP = 600
RADIUS   = 112

SHOTS = [
    ("card",   "電子會員卡，隨時出示", "掃碼入場、領取新生包，或在合作商家享折扣。"),
    ("home",   "重要的事，一開就看見", "公告、活動與優惠，首頁一次看完。"),
    ("events", "活動報名與電子票券",   "連結活動網站帳號，報名與票券直接帶著走。"),
    ("ticket", "票券就在手機裡",       "到現場打開就能掃，不用翻信箱找信。"),
    ("deals",  "合作商家專屬優惠",     "出示電子會員卡，即享專屬禮遇。"),
]


def gradient():
    """Vertical brand-red wash. Built row by row rather than resized from a
    two-pixel strip so there is no banding at this height."""
    g = Image.new("RGB", (1, H))
    px = g.load()
    for y in range(H):
        t = y / (H - 1)
        px[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(BRAND_TOP, BRAND_BOTTOM))
    return g.resize((W, H), Image.BICUBIC)


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return m


def build(name, headline, subline):
    canvas = gradient()

    shot = Image.open(os.path.join(RAW, f"{name}.png")).convert("RGB")
    scale = SHOT_W / shot.width
    shot = shot.resize((SHOT_W, round(shot.height * scale)), Image.LANCZOS)
    x = (W - SHOT_W) // 2

    # Shadow first, offset down so the phone reads as lifted off the wash.
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = Image.new("RGBA", shot.size, (0, 0, 0, 150))
    sd.putalpha(rounded_mask(shot.size, RADIUS).point(lambda v: v * 150 // 255))
    shadow.paste(sd, (x, SHOT_TOP + 26), sd)
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)

    canvas.paste(shot, (x, SHOT_TOP), rounded_mask(shot.size, RADIUS))

    draw = ImageDraw.Draw(canvas)
    head = ImageFont.truetype(FONT, HEAD_PX, index=SEMI)
    sub  = ImageFont.truetype(FONT, SUB_PX,  index=REG)
    draw.text((MARGIN, HEAD_Y), headline, font=head, fill=(255, 255, 255, 255))
    draw.text((MARGIN, HEAD_Y + HEAD_PX + 40), subline, font=sub, fill=(255, 255, 255, 200))

    out = os.path.join(OUT, f"{SHOTS.index((name, headline, subline)) + 1:02d}-{name}.png")
    canvas.convert("RGB").save(out)
    print(out, canvas.size)


for s in SHOTS:
    build(*s)
