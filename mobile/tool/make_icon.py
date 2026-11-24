"""Vẽ logo Smart Canteen: bát cơm bốc khói (trắng) — xuất 3 file vào thư mục đích.

  icon.png            1024² nền cam bo góc (iOS / web / icon cũ)
  icon_foreground.png 1024² nền trong suốt, hình nằm gọn vùng an toàn 66% (adaptive icon Android)
  splash.png          1152² nền trong suốt, hình màu cam (màn chờ, Android 12 cắt tròn)
"""
import math
import os
import sys

from PIL import Image, ImageDraw

BRAND = (245, 124, 0, 255)
WHITE = (255, 255, 255, 255)
S = 4  # vẽ ở 4x rồi thu nhỏ để khử răng cưa


def glyph(draw, cx, cy, scale, color):
    """Bát + 3 làn khói, tâm (cx, cy), kích thước gốc ~560px * scale."""
    def p(x, y):
        return (cx + x * scale) * S, (cy + y * scale) * S

    # Thân bát: nửa dưới hình elip.
    x0, y0 = p(-280, -200)
    x1, y1 = p(280, 220)
    draw.pieslice([x0, y0, x1, y1], 0, 180, fill=color)
    # Miệng bát: dải bo tròn.
    rx0, ry0 = p(-312, -10)
    rx1, ry1 = p(312, 40)
    draw.rounded_rectangle([rx0, ry0, rx1, ry1], radius=25 * scale * S, fill=color)
    # Chân bát.
    fx0, fy0 = p(-92, 200)
    fx1, fy1 = p(92, 246)
    draw.rounded_rectangle([fx0, fy0, fx1, fy1], radius=20 * scale * S, fill=color)
    # Khói: 3 đường lượn sóng, đầu tròn.
    width = 34 * scale * S
    for dx in (-112, 0, 112):
        # Chuỗi hình tròn dày đặc dọc đường sin → nét liền, đầu tròn, không có vết nối.
        r = width / 2
        for i in range(0, 801):
            t = i / 20
            x, y = p(dx + 26 * math.sin(t / 40 * 2 * math.pi), -60 - t * 5.2)
            draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


def canvas(size):
    return Image.new("RGBA", (size * S, size * S), (0, 0, 0, 0))


def save(img, size, path):
    img.resize((size, size), Image.LANCZOS).save(path)
    print("saved", path)


out = sys.argv[1]
os.makedirs(out, exist_ok=True)

# 1) Icon đầy đủ: nền cam bo góc 22%, hình chiếm ~60%.
img = canvas(1024)
d = ImageDraw.Draw(img)
d.rounded_rectangle([0, 0, 1024 * S, 1024 * S], radius=225 * S, fill=BRAND)
glyph(d, 512, 560, 0.9, WHITE)
save(img, 1024, os.path.join(out, "icon.png"))

# 2) Foreground adaptive: hình nhỏ hơn để nằm trong vùng an toàn (launcher có thể cắt tròn).
img = canvas(1024)
glyph(ImageDraw.Draw(img), 512, 532, 0.85, WHITE)
save(img, 1024, os.path.join(out, "icon_foreground.png"))

# 3) Splash: hình cam trên nền trong suốt (nền sáng/tối do màn chờ quyết định).
img = canvas(1152)
glyph(ImageDraw.Draw(img), 576, 620, 0.72, BRAND)
save(img, 1152, os.path.join(out, "splash.png"))
