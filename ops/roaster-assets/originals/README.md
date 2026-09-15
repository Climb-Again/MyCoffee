# Roaster logo originals — the as-dropped files

Recovered from git history on 2026-09-15 at Radu's request ("restore logos").

**These are NOT served.** The files the app and the DB point at are the 64
normalized WebPs in `../logos/`, published via
`raw.githubusercontent.com/Climb-Again/MyCoffee/main/ops/roaster-assets/logos/<slug>.webp`.
This folder is the archive you re-normalize *from* when the output rules change
(a different max dimension, a different quality, a smarter crop) — without it,
every such change would compound loss on an already-lossy file.

## Why they had to be recovered rather than just read off disk

`normalize-logos.py` converts **in place**: it writes `<stem>.webp` next to the
source and then `os.remove(path)` when the source extension was not already
`.webp`. So each import batch deleted its own inputs. They were committed first,
which is the only reason they still exist at all.

## What is here

63 files, ~1.3 MB, under their original human names:

| Format | Count |
|---|---|
| PNG | 22 |
| JPEG | 21 |
| JPG | 8 |
| WebP | 10 |
| AVIF | 2 |

Coverage against the 64 shipped logos: **58 map to a shipped slug directly**, and
5 more map under a rename the import did by hand (`BirdSong` →
`birdsong-coffee`, `HAYB` → `hayb-speciality-coffee`, `Keen` → `keen-coffee`,
`three marks` → `three-marks-coffee`, `manhattan` →
`manhattan-coffee-roasters`).

**4 shipped logos have no original here** — `a-m-o-c`, `boo-modern-coffee`,
`coffea-circulor`, `father-s-coffee-roastery`. Those were dropped already named
`<slug>.webp`, so `normalize-logos.py` re-encoded them in place and never
deleted a source (its `os.remove` is gated on the extension not being `.webp`).
For those four the shipped file is the only copy, and it has been through one
q85 re-encode.

## What normalization actually costs

Measured 2026-09-15, not assumed:

- **20 of 61** originals had a longest side above the 512 px cap, so those were
  downscaled. The other 41 were already at or under it and lost nothing to
  resizing.
- **Alpha is preserved.** The script converts RGBA/LA/P sources to `RGBA` and
  only non-alpha sources to `RGB`, then saves WebP — it does not flatten
  transparency onto a background.
- Every output is q85, `method=6`.

## Adding a new logo

Drop it in `../logos/` and run `python3 ../normalize-logos.py`. **Copy the
original in here first** — the script will delete it from `logos/` otherwise,
and you will be recovering it from git again.

`normalize-logos.py` globs `logos/*` only, so nothing in this folder is ever
touched by it.
