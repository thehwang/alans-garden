"""Turn the light-gray-backed flower renders into clean transparent, tightly
cropped square PNGs. Flood-fills the background from the corners (interior dew
highlights stay opaque), feathers the edge, then crops to a centered square."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SENTINEL = (255, 0, 255)

for name in ["flower-A.png", "flower-B.png", "flower-C.png"]:
    im = Image.open(name).convert("RGB")
    w, h = im.size
    for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(im, corner, SENTINEL, thresh=72)

    arr = np.array(im.convert("RGBA"))
    bg = (arr[:, :, 0] == 255) & (arr[:, :, 1] == 0) & (arr[:, :, 2] == 255)
    arr[bg] = [0, 0, 0, 0]
    rgba = Image.fromarray(arr)

    # Kill the 1px gray halo, then soften the cutout edge.
    alpha = rgba.split()[3].filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1))
    rgba.putalpha(alpha)

    box = rgba.getbbox()
    cropped = rgba.crop(box)
    cw, ch = cropped.size
    side = max(cw, ch)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(cropped, ((side - cw) // 2, (side - ch) // 2), cropped)
    canvas.save(name)
    print(name, "->", canvas.size)
