# Roaster assets — logos + blurbs

Content intake for roaster pages (backlog **#132–#135**). This folder is where
Radu drops roaster logos and where roaster blurbs are staged before the Data lane
(#133) writes them into the DB (`roasters.blurb` + a new `roasters.logo_url`).

## Logos → `logos/`

Drop one image per roaster in `logos/`. **Name the file by roaster** — I map the
name to the roaster's `slug` (the stable DB key) automatically, so casing and
punctuation don't matter:

- `DAK Coffee Roasters.png` → `dak-coffee-roasters`
- `The Naughty Dog.jpg` → `the-naughty-dog`

PNG or JPG, square-ish, ideally ≥256 px. See `CHECKLIST.md` for every roaster's
exact slug and how many coffees it has (fill the high-count ones first).

> ⚠️ **Hosting is still an open decision (#132).** Committing logo files here is
> the intake step; how they're *served* to the app (a CDN `logo_url` fetched
> through the app's image cache vs. serving them from the backend) is Radu's call,
> because the app has a hard 30 MB image-cache / 50 MB app-size budget (CLAUDE.md
> §12). Don't wire serving without that decision.

## Blurbs → `blurbs.md`

Paste blurbs in chat and they get staged into `blurbs.md`, one section per roaster
keyed by slug:

```
## dak-coffee-roasters
Amsterdam roasters known for playful, design-led bags and bright, fruit-forward
light roasts.
```

## Checklist

`CHECKLIST.md` is generated from the live backend snapshot and shows, per roaster,
whether a logo and blurb are present yet. Regenerate after adding content:

```bash
python3 ops/roaster-assets/gen-checklist.py
```

Nothing in this folder deploys or builds — `ops/**` matches no workflow path
filter.
