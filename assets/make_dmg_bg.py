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
    layer = Image.new("L", size, 0)
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius], fill=alpha)
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.6))
    return Image.new("RGB", size, color), layer


# ---------- 底色：接近白的粉紫，颜色只在四周淡淡晕开 ----------
img = Image.new("RGB", (W, H), (253, 251, 254))
d = ImageDraw.Draw(img)
for y in range(H):
    t = y / (H - 1)
    r = int(254 + (250 - 254) * t)
    g = int(251 + (246 - 251) * t)
    b = int(255 + (253 - 255) * t)
    d.line([(0, y), (W, y)], fill=(r, g, b))

blobs = [
    ((W * 0.10, H * 0.10), W * 0.52, (248, 205, 235), 58),   # 左上淡粉
    ((W * 0.94, H * 0.18), W * 0.42, (224, 205, 252), 54),   # 右上淡紫
    ((W * 0.72, H * 1.02), W * 0.62, (214, 196, 250), 60),   # 右下淡紫
    ((W * 0.10, H * 0.98), W * 0.34, (247, 214, 240), 42),    # 左下粉
]
for (center, radius, color, alpha) in blobs:
    solid, mask = radial_blob((W, H), center, radius, color, alpha)
    img = Image.composite(solid, img, mask)

# ---------- 文字层（带一点透明度，和背景融合） ----------
overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
od = ImageDraw.Draw(overlay)

title = "安装 V2A"
f_title = font(23, weight=1)
tw = od.textlength(title, font=f_title)
od.text(((W - tw) / 2, 70), title, font=f_title, fill=(52, 20, 88, 235))

sub = "Video to Audio for macOS"
f_sub = font(13)
sw = od.textlength(sub, font=f_sub)
od.text(((W - sw) / 2, 132), sub, font=f_sub, fill=(110, 80, 165, 190))

# ---------- 箭头：两端留出相同间距，存在感降低 ----------
arrow_y = 384
x0, x1 = 408, 644            # 2x 像素 = 212 → 330pt，左右各约 22pt 空档
shaft_end = x1 - 34
od.line([(x0, arrow_y), (shaft_end, arrow_y)], fill=(139, 92, 246, 150), width=8)
od.polygon([(shaft_end - 2, arrow_y - 22), (x1, arrow_y), (shaft_end - 2, arrow_y + 22)],
           fill=(139, 92, 246, 150))

# ---------- 底部提示：中英靠近，整体下移 ----------
tip = "把左边的 V2A 拖到右边的 Applications 文件夹"
f_tip = font(13.5)
pw = od.textlength(tip, font=f_tip)
od.text(((W - pw) / 2, 556), tip, font=f_tip, fill=(72, 40, 120, 200))

tip_en = "Drag V2A onto Applications to install"
f_en = font(12)
ew = od.textlength(tip_en, font=f_en)
od.text(((W - ew) / 2, 598), tip_en, font=f_en, fill=(120, 96, 165, 165))

img = Image.alpha_composite(img.convert("RGBA"), overlay).convert("RGB")

out = os.path.join(HERE, "dmg", "background.png")
# 144dpi：像素 1080×760，点尺寸正好 540×380，Retina 上不发虚
img.save(out, dpi=(144, 144))
print("ok:", out, img.size)
