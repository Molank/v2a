#!/usr/bin/env python3
"""生成 DMG 安装窗口的背景图（540×380 点，2x 像素 + 144dpi，Finder 里不会糊）。"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1080, 760          # 2x 像素
HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size, weight=0):
    return ImageFont.truetype(FONT, size * 2, index=2 if weight else 0)


def radial_blob(size, center, radius, color, alpha):
    """一团模糊的径向色块，用来做弥散渐变"""
    layer = Image.new("L", size, 0)
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=alpha)
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.55))
    solid = Image.new("RGB", size, color)
    return solid, layer


# ---------- 底色：粉紫 → 紫的弥散渐变 ----------
img = Image.new("RGB", (W, H), (250, 245, 255))
d = ImageDraw.Draw(img)
for y in range(H):
    t = y / (H - 1)
    r = int(251 + (237 - 251) * t)
    g = int(240 + (224 - 240) * t)
    b = int(252 + (255 - 252) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))

blobs = [
    ((W * 0.18, H * 0.22), W * 0.42, (244, 171, 252), 190),   # 左上粉紫
    ((W * 0.86, H * 0.26), W * 0.38, (192, 132, 252), 175),   # 右上紫
    ((W * 0.50, H * 0.92), W * 0.55, (167, 139, 250), 150),   # 底部紫
    ((W * 0.06, H * 0.86), W * 0.30, (240, 171, 252), 120),   # 左下粉
]
for (center, radius, color, alpha) in blobs:
    solid, mask = radial_blob((W, H), center, radius, color, alpha)
    img = Image.composite(solid, img, mask.point(lambda v: int(v * 0.55)))

# 顶部压一层很淡的白，保证标题对比
veil = Image.new("L", (W, H), 0)
vd = ImageDraw.Draw(veil)
for y in range(int(H * 0.42)):
    vd.line([(0, y), (W, y)], fill=int(70 * (1 - y / (H * 0.42)) ** 1.4))
veil = veil.filter(ImageFilter.GaussianBlur(24))
img = Image.composite(Image.new("RGB", (W, H), (255, 255, 255)), img, veil)

d = ImageDraw.Draw(img)

# ---------- 标题 ----------
title = "安装 V2A"
f_title = font(23, weight=1)
tw = d.textlength(title, font=f_title)
d.text(((W - tw) / 2, 70), title, font=f_title, fill=(59, 7, 100))

sub = "Video to Audio for macOS"
f_sub = font(13)
sw = d.textlength(sub, font=f_sub)
d.text(((W - sw) / 2, 150), sub, font=f_sub, fill=(124, 58, 237))

# ---------- 箭头：两端都留出空档，居中 ----------
arrow_y = 384
x0, x1 = 402, 704          # 2x 像素；对应点 201 → 352
shaft_end = x1 - 42
d.line([(x0, arrow_y), (shaft_end, arrow_y)], fill=(139, 92, 246), width=10)
d.polygon([(shaft_end - 4, arrow_y - 27), (x1, arrow_y), (shaft_end - 4, arrow_y + 27)],
          fill=(139, 92, 246))

# ---------- 底部提示 ----------
tip = "把左边的 V2A 拖到右边的 Applications 文件夹"
f_tip = font(15)
pw = d.textlength(tip, font=f_tip)
d.text(((W - pw) / 2, 540), tip, font=f_tip, fill=(76, 29, 149))

tip_en = "Drag V2A onto Applications to install"
f_en = font(12)
ew = d.textlength(tip_en, font=f_en)
d.text(((W - ew) / 2, 596), tip_en, font=f_en, fill=(146, 118, 200))

out = os.path.join(HERE, "dmg", "background.png")
# 144dpi：像素 1080×760，点尺寸正好 540×380，Retina 上不发虚
img.save(out, dpi=(144, 144))
print("ok:", out, img.size)
