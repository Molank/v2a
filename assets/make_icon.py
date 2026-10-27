#!/usr/bin/env python3
"""生成 V2A 的 App 图标：紫色 squircle + 白色声波，带轻拟物的顶光与内阴影。"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 1024
SS = 4                      # 超采样倍数
W = S * SS
HERE = os.path.dirname(os.path.abspath(__file__))


def vertical_gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        d.line([(0, y), (size, y)],
               fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return img


def diagonal_gradient(size, start, end):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(0, size, 2):
            t = (x / (size - 1) * 0.45) + (y / (size - 1) * 0.55)
            c = tuple(int(start[i] + (end[i] - start[i]) * t) for i in range(3))
            px[x, y] = c
            if x + 1 < size:
                px[x + 1, y] = c
    return img


# ---------- 基础层 ----------
base = vertical_gradient(W, (72, 56, 176), (124, 58, 237)).convert("RGBA")

# 顶部中央一团很淡的高光，模拟受光
glow = Image.new("L", (W, W), 0)
ImageDraw.Draw(glow).ellipse([W * 0.10, -W * 0.42, W * 0.90, W * 0.34], fill=40)
glow = glow.filter(ImageFilter.GaussianBlur(W * 0.09))
base = Image.composite(Image.new("RGB", (W, W), (255, 255, 255)), base.convert("RGB"),
                       glow).convert("RGBA")

# ---------- squircle 遮罩 ----------
inset = int(W * 0.098)
box = [inset, inset, W - inset, W - inset]
radius = int((box[2] - box[0]) * 0.235)
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)

icon = Image.new("RGBA", (W, W), (0, 0, 0, 0))
icon.paste(base, (0, 0), mask)

# ---------- 顶部柔光 ----------
gloss = Image.new("L", (W, W), 0)
gd = ImageDraw.Draw(gloss)
top = box[1]
bottom = box[1] + int((box[3] - box[1]) * 0.55)
for y in range(top, bottom):
    t = (y - top) / max(bottom - top, 1)
    gd.line([(0, y), (W, y)], fill=int(34 * (1 - t) ** 1.8))
gloss = gloss.filter(ImageFilter.GaussianBlur(W * 0.012))
light = Image.new("RGBA", (W, W), (255, 255, 255, 255))
light.putalpha(gloss)
layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
layer.paste(light, (0, 0), mask)
icon = Image.alpha_composite(icon, layer)

# ---------- 内圈高光（顶部） ----------
rim = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(rim).rounded_rectangle(
    [box[0] + 3 * SS, box[1] + 3 * SS, box[2] - 3 * SS, box[3] - 3 * SS],
    radius=radius - 3 * SS, outline=(255, 255, 255, 255), width=int(2.4 * SS))

fade = Image.new("L", (W, W), 0)
fd = ImageDraw.Draw(fade)
for y in range(W):
    t = y / (W - 1)
    fd.line([(0, y), (W, y)], fill=int(130 * max(0.0, 1 - t * 1.6)))
rim.putalpha(rim.getchannel("A").point(lambda v: v * 105 // 255))
rim.putalpha(Image.composite(rim.getchannel("A"), Image.new("L", (W, W), 0), fade))
icon = Image.alpha_composite(icon, rim)

# ---------- 内阴影（底部） ----------
inner = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(inner).rounded_rectangle(
    [box[0] + 5 * SS, box[1] + 5 * SS, box[2] - 5 * SS, box[3] - 5 * SS],
    radius=radius - 5 * SS, outline=(20, 8, 60, 255), width=int(3 * SS))
inner = inner.filter(ImageFilter.GaussianBlur(2 * SS))
fade2 = Image.new("L", (W, W), 0)
fd2 = ImageDraw.Draw(fade2)
for y in range(W):
    t = y / (W - 1)
    fd2.line([(0, y), (W, y)], fill=int(120 * max(0.0, (t - 0.45)) / 0.55))
inner.putalpha(Image.composite(inner.getchannel("A"), Image.new("L", (W, W), 0), fade2))
icon = Image.alpha_composite(icon, inner)

# ---------- 声波条 ----------
cx, cy = W / 2, W / 2
heights = [0.20, 0.345, 0.46, 0.345, 0.20]
bar_w = 53 * SS
bar_gap = 48 * SS
total = len(heights) * bar_w + (len(heights) - 1) * bar_gap
x = cx - total / 2

bars_mask = Image.new("L", (W, W), 0)
bd = ImageDraw.Draw(bars_mask)
for h in heights:
    half = W * h / 2
    bd.rounded_rectangle([x, cy - half, x + bar_w, cy + half], radius=bar_w // 2, fill=255)
    x += bar_w + bar_gap

# 条下方的柔和投影
bar_shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
shadow_mask = bars_mask.filter(ImageFilter.GaussianBlur(7 * SS))
bar_shadow.paste((10, 4, 40, 110), (0, 0), shadow_mask)
bar_shadow = bar_shadow.transform(
    bar_shadow.size, Image.AFFINE, (1, 0, 0, 0, 1, -3 * SS), resample=Image.BILINEAR)
icon = Image.alpha_composite(icon, bar_shadow)

# 白条自身带一点渐变，避免死白
bar_fill = vertical_gradient(W, (255, 255, 255), (232, 226, 255)).convert("RGBA")
bars = Image.new("RGBA", (W, W), (0, 0, 0, 0))
bars.paste(bar_fill, (0, 0), bars_mask)
icon = Image.alpha_composite(icon, bars)

# ---------- 外投影 ----------
sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(sh).rounded_rectangle(
    [box[0] + 6 * SS, box[1] + 20 * SS, box[2] - 6 * SS, box[3] + 10 * SS],
    radius=radius, fill=(24, 12, 60, 96))
sh = sh.filter(ImageFilter.GaussianBlur(24 * SS))
canvas = Image.new("RGBA", (W, W), (0, 0, 0, 0))
canvas = Image.alpha_composite(canvas, sh.filter(ImageFilter.GaussianBlur(6 * SS)))
canvas = Image.alpha_composite(canvas, icon)

master = canvas.resize((S, S), Image.LANCZOS)
master.save(os.path.join(HERE, "icon-1024.png"))

iconset = os.path.join(HERE, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)
for base_size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        px = base_size * scale
        name = f"icon_{base_size}x{base_size}{'@2x' if scale == 2 else ''}.png"
        master.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))
print("ok:", master.size)
