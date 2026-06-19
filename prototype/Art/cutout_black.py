"""Key the solid black background out of the redrawn flowers and save tight,
transparent, square PNGs (overwriting flower-A/B)."""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SENTINEL = (255, 0, 255)

for src, dst in [("flower-A-new.png", "flower-A.png"), ("flower-B-new.png", "flower-B.png")]:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    for c in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(im, c, SENTINEL, thresh=60)

    arr = np.array(im.convert("RGBA"))
    bg = (arr[:, :, 0] == 255) & (arr[:, :, 1] == 0) & (arr[:, :, 2] == 255)
    arr[bg] = [0, 0, 0, 0]
    rgba = Image.fromarray(arr)

    alpha = rgba.split()[3].filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1))
    rgba.putalpha(alpha)

    cropped = rgba.crop(rgba.getbbox())
    cw, ch = cropped.size
    side = max(cw, ch)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(cropped, ((side - cw) // 2, (side - ch) // 2), cropped)
    canvas.save(dst)
    print(dst, "->", canvas.size)
