#!/usr/bin/env python3
"""Normalize roaster logos to WebP to minimize weight (backlog #133).

Converts every file in logos/ to WebP, caps the longest side at 512px (a roaster
page header never needs more), preserves transparency, and keeps the slug stem.
Idempotent: a file already ≤512px WebP re-encodes to a near-identical size, so
re-running is cheap and safe. Non-WebP sources are removed after conversion.

    python3 ops/roaster-assets/normalize-logos.py

Needs Pillow + pillow-avif-plugin (for reading .avif):
    pip install pillow pillow-avif-plugin

Prints an old→new size table. After running, regenerate the checklist:
    python3 ops/roaster-assets/gen-checklist.py
"""
import glob
import os

from PIL import Image

try:
    import pillow_avif  # noqa: F401  enables AVIF reading
except Exception:
    pass  # only needed if an .avif is present

HERE = os.path.dirname(os.path.abspath(__file__))
LOGOS = os.path.join(HERE, "logos")
MAX = 512
QUALITY = 85


def main():
    rows = []
    for path in sorted(glob.glob(os.path.join(LOGOS, "*"))):
        name = os.path.basename(path)
        if name == ".gitkeep":
            continue
        stem, ext = os.path.splitext(name)
        old = os.path.getsize(path)
        im = Image.open(path)
        has_alpha = im.mode in ("RGBA", "LA", "P") and (
            "A" in im.getbands() or im.mode == "P"
        )
        im = im.convert("RGBA") if has_alpha else im.convert("RGB")
        w, h = im.size
        if max(w, h) > MAX:
            s = MAX / max(w, h)
            im = im.resize((round(w * s), round(h * s)), Image.LANCZOS)
        out = os.path.join(LOGOS, stem + ".webp")
        tmp = out + ".tmp"
        im.save(tmp, "WEBP", quality=QUALITY, method=6)
        os.replace(tmp, out)
        if ext.lower() != ".webp":
            os.remove(path)
        rows.append((name, stem + ".webp", old, os.path.getsize(out)))

    if not rows:
        print("no logos to normalize")
        return
    to = sum(r[2] for r in rows)
    tn = sum(r[3] for r in rows)
    print(f"{'file':32} {'old':>8} {'new':>8}")
    for src, dst, o, n in rows:
        note = "" if src == dst else f"  (was {src})"
        print(f"{dst:32} {o:8} {n:8}{note}")
    pct = (100 * (to - tn) // to) if to else 0
    print(f"{'TOTAL':32} {to:8} {tn:8}  ({pct}% smaller)")


if __name__ == "__main__":
    main()
