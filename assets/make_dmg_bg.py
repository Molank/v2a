#!/usr/bin/env python3
"""生成 DMG 安装窗口的背景图（540×360，2x 输出）。"""
import os
from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 720          # 2x
HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size, weight=0):
    return ImageFont.truetype(FONT, size * 2, index=2 if weight else 0)


img = Image.new("RGB", (W, H), (245, 245, 247))
d = ImageDraw.Draw(img)

# 顶部标题
title = "安装 V2A"
f_title = font(22, weight=1)
tw = d.textlength(title, font=f_title)
d.text(((W - tw) / 2, 64), title, font=f_title, fill=(28, 28, 30))

sub = "Video to Audio for macOS"
f_sub = font(13)
sw = d.textlength(sub, font=f_sub)
d.text(((W - sw) / 2, 132), sub, font=f_sub, fill=(120, 120, 125))

# 中间箭头（从左图标指向右文件夹）
arrow_y = 372
x0, x1 = 330, 700
d.line([(x0, arrow_y), (x1 - 34, arrow_y)], fill=(150, 132, 240), width=9)
d.polygon([(x1 - 40, arrow_y - 26), (x1, arrow_y), (x1 - 40, arrow_y + 26)],
          fill=(150, 132, 240))

# 底部说明
tip = "把左边的 V2A 拖到右边的 Applications 文件夹"
f_tip = font(15)
pw = d.textlength(tip, font=f_tip)
d.text(((W - pw) / 2, 566), tip, font=f_tip, fill=(90, 90, 95))

tip_en = "Drag V2A onto Applications to install"
f_en = font(12)
ew = d.textlength(tip_en, font=f_en)
d.text(((W - ew) / 2, 612), tip_en, font=f_en, fill=(160, 160, 165))

out = os.path.join(HERE, "dmg", "background.png")
img.resize((540, 360), Image.LANCZOS).save(out)
print("ok:", out)
