#!/usr/bin/env python3
"""Mac exporter + uploader for the "Coffees" Photos album (PLAN.md §3, §9).

Two-phase upload against the MyCoffee backend, matching backend/src/routes/photos.js:

  1. POST /api/photos/manifest  -- cheap metadata batch (<=200 entries); the
     server replies per photo with need: "image" | "none".
  2. PUT  /api/photos/:sourceId/image?sha256=<hex> -- only for photos the
     manifest flagged, raw JPEG body.

`osxphotos` (`pip install osxphotos`) reads the Photos library and metadata
that PHAsset/PhotoKit cannot expose (title/description live in the Photos
database, not the asset -- CLAUDE.md §12); macOS's built-in `sips` converts
each original (often HEIC) to the same JPEG shape as the server's "ocr"
derivative, since prebuilt sharp/libvips binaries commonly lack HEIF decode
support. Both are macOS-only, so this script only runs end-to-end on Radu's
Mac -- see ops/README.md for the manual run + the PLAN.md §8 20-photo gate.

Everything above the "macOS-specific I/O" marker below is pure (no Photos
library, no network, no subprocess) and is unit-tested on any platform in
ops/test_mycoffee_export.py.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator, Optional

MANIFEST_BATCH_SIZE = 200  # hard server limit, routes/photos.js MANIFEST_MAX_ENTRIES
RETRY_DELAYS_S = (2, 5, 15, 45, 120)  # mirrors the extraction worker backoff, PLAN.md §2
OCR_MAX_DIM = 2048  # matches the server's 'ocr' derivative spec, routes/photos.js
OCR_JPEG_QUALITY = 85
DEFAULT_ALBUM = "coffees"
DEFAULT_BACKEND_URL = "https://mycoffee-production-bd43.up.railway.app"
DEFAULT_STATE_PATH = Path.home() / "Library" / "Application Support" / "MyCoffee" / "export_state.json"


# ---------------------------------------------------------------------------
# Pure logic
# ---------------------------------------------------------------------------


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def chunked(items, size):
    """Split into lists of at most `size` -- keeps every manifest POST under
    the server's MANIFEST_MAX_ENTRIES (200)."""
    items = list(items)
    if size <= 0:
        raise ValueError("size must be positive")
    for i in range(0, len(items), size):
        yield items[i : i + size]


@dataclass
class PhotoRecord:
    """One photo from the Coffees album. The macOS-specific glue (osxphotos)
    builds these; everything else only reads the dataclass fields, so tests
    can construct one directly without a Photos library."""

    source_id: str
    captured_at: Optional[datetime]
    title: Optional[str]
    description: Optional[str]
    favorite: bool
    original_path: str
    file_size: int
    file_mtime_ns: int


def file_signature(size: int, mtime_ns: int) -> str:
    """Cheap per-run change detector for an on-disk original -- (size, mtime)
    rather than hashing the file, so a repeat run over an unchanged library
    costs a stat() per photo, not a full sips conversion."""
    return f"{size}:{mtime_ns}"


def captured_on_of(captured_at: Optional[datetime]) -> Optional[str]:
    if captured_at is None:
        return None
    return captured_at.strftime("%Y-%m-%d")


def captured_at_iso(captured_at: Optional[datetime]) -> Optional[str]:
    if captured_at is None:
        return None
    # osxphotos' PhotoInfo.date is normally timezone-aware; tolerate naive
    # datetimes by treating them as the machine's local time (the Mac the
    # export runs on), same source as the Photos library itself.
    dt = captured_at if captured_at.tzinfo is not None else captured_at.astimezone()
    return dt.astimezone(timezone.utc).isoformat()


def build_manifest_entry(record: PhotoRecord, content_sha256: str) -> dict:
    """Shape one backend/src/routes/photos.js manifest entry.

    `caption` is always null: Photos.app exposes exactly one free-text field
    beyond Title (osxphotos surfaces it as `.description`) -- there is no
    distinct "caption" in the real metadata. The server schema keeps the
    field so other sources could populate it; see ops/README.md.
    """
    entry = {
        "sourceId": record.source_id,
        "contentSha256": content_sha256,
        "favorite": bool(record.favorite),
        "title": record.title,
        "caption": None,
        "description": record.description,
    }
    captured_at = captured_at_iso(record.captured_at)
    if captured_at is not None:
        entry["capturedAt"] = captured_at
        entry["capturedOn"] = captured_on_of(record.captured_at)
    return entry


def load_state(path) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(path, state: dict) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp-{os.getpid()}")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, sort_keys=True)
    tmp.replace(path)


def needs_conversion(record: PhotoRecord, state: dict) -> bool:
    """True unless a prior successful run already converted+hashed this exact
    file (matched by (size, mtime)) -- lets a repeat run skip the sips
    conversion entirely for every unchanged photo."""
    cached = state.get(record.source_id)
    if not cached:
        return True
    return cached.get("signature") != file_signature(record.file_size, record.file_mtime_ns)


# ---------------------------------------------------------------------------
# macOS-specific I/O -- osxphotos + sips. Imports are lazy so the pure logic
# above (and its tests) works on any platform.
# ---------------------------------------------------------------------------


def iter_album_photos(album: str, limit: Optional[int] = None) -> Iterator[PhotoRecord]:
    import osxphotos  # local import: only available/needed on macOS

    db = osxphotos.PhotosDB()
    count = 0
    for p in db.photos(albums=[album]):
        if p.ismissing:
            print(f"warning: {p.uuid} has no local original (not downloaded from iCloud) -- skipping", file=sys.stderr)
            continue
        path = p.path or p.path_edited
        if not path:
            print(f"warning: {p.uuid} has no exportable file path -- skipping", file=sys.stderr)
            continue
        stat = os.stat(path)
        yield PhotoRecord(
            source_id=p.uuid,
            captured_at=p.date,
            title=(p.title or None),
            description=(p.description or None),
            favorite=bool(p.favorite),
            original_path=path,
            file_size=stat.st_size,
            file_mtime_ns=stat.st_mtime_ns,
        )
        count += 1
        if limit is not None and count >= limit:
            return


def convert_to_jpeg(src_path: str, max_dim: int = OCR_MAX_DIM, quality: int = OCR_JPEG_QUALITY) -> bytes:
    """Resize+convert via macOS `sips` (no new Python deps) to the same
    2048px JPEG shape as the server's 'ocr' derivative (routes/photos.js) --
    a HEIC original should never reach sharp, since prebuilt sharp/libvips
    binaries commonly lack HEIF decode support."""
    with tempfile.TemporaryDirectory(prefix="mycoffee-sips-") as tmp:
        out_path = os.path.join(tmp, "converted.jpg")
        subprocess.run(
            [
                "sips",
                "-s", "format", "jpeg",
                "-s", "formatOptions", str(quality),
                "--resampleHeightWidthMax", str(max_dim),
                src_path,
                "--out", out_path,
            ],
            check=True,
            capture_output=True,
        )
        with open(out_path, "rb") as f:
            return f.read()


# ---------------------------------------------------------------------------
# HTTP client
# ---------------------------------------------------------------------------


class BackendClient:
    def __init__(self, base_url: str, ingest_token: str, timeout: float = 30.0, retry_delays=RETRY_DELAYS_S):
        self.base_url = base_url.rstrip("/")
        self.ingest_token = ingest_token
        self.timeout = timeout
        self.retry_delays = tuple(retry_delays)

    def _request(self, method: str, path: str, *, body: Optional[bytes] = None, content_type: str = "application/json"):
        url = f"{self.base_url}{path}"
        last_err = None
        for delay in (0,) + self.retry_delays:
            if delay:
                time.sleep(delay)
            req = urllib.request.Request(url, data=body, method=method)
            req.add_header("Authorization", f"Bearer {self.ingest_token}")
            req.add_header("Content-Type", content_type)
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    raw = resp.read().decode("utf-8")
                    return resp.getcode(), (json.loads(raw) if raw else None)
            except urllib.error.HTTPError as e:
                raw = e.read().decode("utf-8")
                payload = json.loads(raw) if raw else None
                if e.code < 500:
                    # Not transient (bad request, auth, sha256 mismatch) --
                    # retrying would just repeat the same failure.
                    return e.code, payload
                last_err = e
            except urllib.error.URLError as e:
                last_err = e
        raise RuntimeError(f"{method} {path} failed after {len(self.retry_delays) + 1} attempts: {last_err}")

    def post_manifest(self, entries: list) -> dict:
        body = json.dumps({"entries": entries}).encode("utf-8")
        code, payload = self._request("POST", "/api/photos/manifest", body=body)
        if code != 200:
            raise RuntimeError(f"manifest POST returned {code}: {payload}")
        return payload

    def put_image(self, source_id: str, sha256_hex: str, data: bytes) -> dict:
        encoded_id = urllib.parse.quote(source_id, safe="")
        path = f"/api/photos/{encoded_id}/image?sha256={sha256_hex}"
        code, payload = self._request("PUT", path, body=data, content_type="image/jpeg")
        if code not in (200, 201):
            raise RuntimeError(f"image PUT for {source_id} returned {code}: {payload}")
        return payload


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--album", default=DEFAULT_ALBUM, help=f"Photos album name (default: {DEFAULT_ALBUM})")
    parser.add_argument("--backend-url", default=os.environ.get("MYCOFFEE_BACKEND_URL", DEFAULT_BACKEND_URL))
    parser.add_argument(
        "--ingest-token",
        default=os.environ.get("MYCOFFEE_INGEST_TOKEN") or os.environ.get("INGEST_TOKEN"),
        help="or set MYCOFFEE_INGEST_TOKEN / INGEST_TOKEN",
    )
    parser.add_argument("--state-file", default=str(DEFAULT_STATE_PATH))
    parser.add_argument("--limit", type=int, default=None, help="only process the first N photos (the PLAN.md 20-photo gate)")
    parser.add_argument("--dry-run", action="store_true", help="build manifest entries locally; make no network calls")
    return parser.parse_args(argv)


def run(args) -> int:
    state = load_state(args.state_file)
    records = list(iter_album_photos(args.album, limit=args.limit))
    print(f"found {len(records)} photo(s) in album {args.album!r}")

    sha_by_source = {}
    entries = []

    with tempfile.TemporaryDirectory(prefix="mycoffee-export-") as tmp_dir:
        converted_path_by_source = {}

        for record in records:
            if needs_conversion(record, state):
                data = convert_to_jpeg(record.original_path)
                sha = sha256_bytes(data)
                out_path = os.path.join(tmp_dir, f"{record.source_id}.jpg")
                with open(out_path, "wb") as f:
                    f.write(data)
                converted_path_by_source[record.source_id] = out_path
                state[record.source_id] = {
                    "signature": file_signature(record.file_size, record.file_mtime_ns),
                    "sha256": sha,
                }
            else:
                sha = state[record.source_id]["sha256"]
            sha_by_source[record.source_id] = sha
            entries.append(build_manifest_entry(record, sha))

        save_state(args.state_file, state)

        if args.dry_run:
            n_batches = sum(1 for _ in chunked(entries, MANIFEST_BATCH_SIZE)) if entries else 0
            print(
                f"dry run: would send {len(entries)} manifest entries in {n_batches} batch(es); "
                f"{len(converted_path_by_source)} photo(s) freshly converted this run"
            )
            return 0

        client = BackendClient(args.backend_url, args.ingest_token)
        to_upload = []
        for batch in chunked(entries, MANIFEST_BATCH_SIZE):
            resp = client.post_manifest(batch)
            for result in resp["results"]:
                flag = " DUPLICATE-CONTENT" if result.get("duplicateContentSha256") else ""
                print(f"  {result['sourceId']}: need={result['need']} state={result['state']}{flag}")
                if result["need"] == "image":
                    to_upload.append(result["sourceId"])

        print(f"{len(to_upload)} photo(s) need an image upload")
        record_by_source = {r.source_id: r for r in records}
        uploaded = 0
        for source_id in to_upload:
            path = converted_path_by_source.get(source_id)
            if path is None:
                # Cache said this file was unchanged, but the server still
                # wants bytes (e.g. a previous run's PUT never completed) --
                # convert on demand rather than trusting the stale skip.
                record = record_by_source[source_id]
                data = convert_to_jpeg(record.original_path)
                path = os.path.join(tmp_dir, f"{source_id}.jpg")
                with open(path, "wb") as f:
                    f.write(data)
            with open(path, "rb") as f:
                data = f.read()
            result = client.put_image(source_id, sha_by_source[source_id], data)
            uploaded += 1
            print(f"  uploaded {source_id}: {result}")

        print(f"done: {uploaded}/{len(to_upload)} image(s) uploaded")
    return 0


def main(argv=None) -> int:
    args = parse_args(argv)
    if not args.dry_run and not args.ingest_token:
        print("error: --ingest-token or MYCOFFEE_INGEST_TOKEN/INGEST_TOKEN must be set", file=sys.stderr)
        return 2
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
