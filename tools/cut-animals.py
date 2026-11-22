#!/usr/bin/env python3
"""Cuts the animal grids in art/ (5x2 grids on a green background) into the animal pictures in animals/.

Needs Pillow and numpy:  python3 -m venv /tmp/img && /tmp/img/bin/pip install pillow numpy
Run:                     /tmp/img/bin/python tools/cut-animals.py
"""
import pathlib, numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "animals"
# Each grid: the picture, its animals row by row, and where each face sits in its cell:
# (center x, center y, square size), as fractions of the cell's width
GRIDS = [
    ("animals-grid.jpg", [["fox", "wolf", "bear", "mouse", "cat"], ["rabbit", "panda", "owl", "raccoon", "lion"]],
     (0.5, 0.62, 1.06),
     dict(rabbit=(0.5, 0.80, 1.18), mouse=(0.5, 0.68, 1.06), owl=(0.5, 0.64, 1.08), lion=(0.5, 0.70, 1.22), bear=(0.5, 0.66, 1.16), fox=(0.5, 0.64, 1.10))),
    ("animals-grid-2.webp", [["dog", "tiger", "penguin", "koala", "monkey"], ["elephant", "giraffe", "deer", "redpanda", "otter"]],
     (0.5, 0.72, 1.06),
     dict(penguin=(0.5, 0.56, 1.10), dog=(0.5, 0.70, 1.18), elephant=(0.5, 0.80, 1.30), otter=(0.5, 0.72, 1.16),
          redpanda=(0.5, 0.72, 1.12), tiger=(0.5, 0.72, 1.12))),
]
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
    OUT.mkdir(exist_ok=True)
    for file, order, default, frames in GRIDS:
        img = Image.open(ROOT / "art" / file).convert("RGB")
        W, H = img.size; cw, ch = W / len(order[0]), H / len(order)
        for ri, row in enumerate(order):
            for ci, name in enumerate(row):
                box = (round(ci * cw) + 3, round(ri * ch) + 3, round((ci + 1) * cw) - 3, round((ri + 1) * ch) - 3)
                cell = key_out_green(img.crop(box))
                w, h = cell.size; fx, fy, fs = frames.get(name, default)
                s = fs * w; cx, cy = fx * w, fy * w
                sq = Image.new("RGBA", (round(s), round(s)), (0, 0, 0, 0))
                sq.paste(cell, (round(s / 2 - cx), round(s / 2 - cy)))
                sq.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / f"{name}.webp", "WEBP", quality=88, method=6)
                print("made", name)

if __name__ == "__main__":
    main()
