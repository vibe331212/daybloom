#!/usr/bin/env python3
"""Cuts art/animals-grid.jpg (a 5x2 grid on a green background) into the animal pictures in animals/.

Needs Pillow and numpy:  python3 -m venv /tmp/img && /tmp/img/bin/pip install pillow numpy
Run:                     /tmp/img/bin/python tools/cut-animals.py
"""
import pathlib, numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "art" / "animals-grid.jpg"
OUT = ROOT / "animals"
ORDER = [["fox", "wolf", "bear", "mouse", "cat"], ["rabbit", "panda", "owl", "raccoon", "lion"]]
# Where each face sits in its cell: (center x, center y, square size), as fractions of the cell's width
FRAME = {k: (0.5, 0.62, 1.06) for row in ORDER for k in row}
FRAME.update(rabbit=(0.5, 0.80, 1.18), mouse=(0.5, 0.68, 1.06), owl=(0.5, 0.64, 1.08), lion=(0.5, 0.70, 1.22), bear=(0.5, 0.66, 1.16), fox=(0.5, 0.64, 1.10))
SIZE = 256

def key_out_green(cell):
    """Turns the green background see-through, keeping green bits inside the animal (like a cat's eyes)."""
    a = np.asarray(cell.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = g - np.maximum(r, b)                      # how much greener than anything else
    bg = green > 22
    # Only green that touches the cell's edge counts as background
    reach = np.zeros_like(bg); reach[0, :] = bg[0, :]; reach[-1, :] = bg[-1, :]; reach[:, 0] = bg[:, 0]; reach[:, -1] = bg[:, -1]
    while True:
        grown = reach.copy()
        grown[1:] |= reach[:-1]; grown[:-1] |= reach[1:]; grown[:, 1:] |= reach[:, :-1]; grown[:, :-1] |= reach[:, 1:]
        grown &= bg
        if (grown == reach).all(): break
        reach = grown
    # Soft edge: fully clear on strong green, fading out over the fur edge
    near = reach.copy()
    for _ in range(3):
        n = near.copy(); n[1:] |= near[:-1]; n[:-1] |= near[1:]; n[:, 1:] |= near[:, :-1]; n[:, :-1] |= near[:, 1:]; near = n
    alpha = np.where(near, 1 - np.clip((green - 6) / 40, 0, 1), 1.0)
    # Remove the green glow left in the fur along the edge
    spill = near & (g > np.maximum(r, b))
    a[..., 1] = np.where(spill, np.maximum(r, b) + (g - np.maximum(r, b)) * 0.15, g)
    rgba = np.dstack([a, alpha * 255]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(rgba)

def main():
    img = Image.open(SRC).convert("RGB")
    W, H = img.size; cw, ch = W / 5, H / 2
    OUT.mkdir(exist_ok=True)
    for ri, row in enumerate(ORDER):
        for ci, name in enumerate(row):
            box = (round(ci * cw) + 3, round(ri * ch) + 3, round((ci + 1) * cw) - 3, round((ri + 1) * ch) - 3)
            cell = key_out_green(img.crop(box))
            w, h = cell.size; fx, fy, fs = FRAME[name]
            s = fs * w; cx, cy = fx * w, fy * w
            sq = Image.new("RGBA", (round(s), round(s)), (0, 0, 0, 0))
            sq.paste(cell, (round(s / 2 - cx), round(s / 2 - cy)))
            sq.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"{name}.webp", "WEBP", quality=88, method=6)
            print("made", name)

if __name__ == "__main__":
    main()
