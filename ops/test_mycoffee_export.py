"""Unit tests for ops/mycoffee_export.py -- covers everything that doesn't
need osxphotos, sips, or a live backend (see the module docstring for the
pure/macOS-specific split). Run with:

    python3 -m unittest ops/test_mycoffee_export.py -v

Cannot be run here: an end-to-end pass against a real "Coffees" Photos
album and macOS's `sips` -- that requires Radu's Mac, per ops/README.md and
the PLAN.md §8 20-photo gate.
"""
import json
import tempfile
import unittest
import urllib.error
from datetime import datetime, timezone
from pathlib import Path
from unittest import mock

import mycoffee_export as export


def make_record(**overrides):
    defaults = dict(
        source_id="uuid-1",
        captured_at=datetime(2019, 6, 15, 10, 30, tzinfo=timezone.utc),
        title="Etiopia Yirgacheffe",
        description="Lot 12, washed, 1600m",
        favorite=False,
        original_path="/tmp/does-not-matter.heic",
        file_size=1234,
        file_mtime_ns=1_000_000_000,
    )
    defaults.update(overrides)
    return export.PhotoRecord(**defaults)


class ExifOrientationTests(unittest.TestCase):
    def test_upright_and_unknown_are_noops(self):
        self.assertEqual(export.exif_orientation_ops(1), [])
        self.assertEqual(export.exif_orientation_ops(0), [])
        self.assertEqual(export.exif_orientation_ops(99), [])

    def test_quarter_turns_map_to_clockwise_rotations(self):
        self.assertEqual(export.exif_orientation_ops(6), ["--rotate", "90"])
        self.assertEqual(export.exif_orientation_ops(3), ["--rotate", "180"])
        self.assertEqual(export.exif_orientation_ops(8), ["--rotate", "270"])

    def test_mirrored_orientations_flip(self):
        self.assertIn("--flip", export.exif_orientation_ops(2))
        self.assertIn("--flip", export.exif_orientation_ops(5))

    def test_ops_are_copies_not_shared_mutable_state(self):
        a = export.exif_orientation_ops(6)
        a.append("--extra")
        self.assertEqual(export.exif_orientation_ops(6), ["--rotate", "90"])


class Sha256Tests(unittest.TestCase):
    def test_sha256_bytes_matches_known_digest(self):
        self.assertEqual(
            export.sha256_bytes(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        )

    def test_sha256_file_matches_sha256_bytes(self):
        with tempfile.NamedTemporaryFile() as f:
            f.write(b"hello coffee")
            f.flush()
            self.assertEqual(export.sha256_file(f.name), export.sha256_bytes(b"hello coffee"))


class ChunkedTests(unittest.TestCase):
    def test_splits_into_batches_of_at_most_size(self):
        batches = list(export.chunked(range(450), 200))
        self.assertEqual([len(b) for b in batches], [200, 200, 50])

    def test_exact_multiple_has_no_trailing_empty_batch(self):
        batches = list(export.chunked(range(400), 200))
        self.assertEqual([len(b) for b in batches], [200, 200])

    def test_empty_input_yields_no_batches(self):
        self.assertEqual(list(export.chunked([], 200)), [])

    def test_rejects_non_positive_size(self):
        with self.assertRaises(ValueError):
            list(export.chunked([1, 2], 0))


class ManifestEntryTests(unittest.TestCase):
    def test_caption_is_always_null(self):
        """Photos.app has no metadata field distinct from `.description` --
        see the build_manifest_entry docstring."""
        entry = export.build_manifest_entry(make_record(), "a" * 64)
        self.assertIsNone(entry["caption"])
        self.assertEqual(entry["description"], "Lot 12, washed, 1600m")

    def test_favorite_is_coerced_to_bool(self):
        entry = export.build_manifest_entry(make_record(favorite=1), "a" * 64)
        self.assertIs(entry["favorite"], True)

    def test_captured_at_present_sets_iso_and_date(self):
        entry = export.build_manifest_entry(
            make_record(captured_at=datetime(2015, 1, 2, 3, 4, 5, tzinfo=timezone.utc)), "a" * 64
        )
        self.assertEqual(entry["capturedOn"], "2015-01-02")
        self.assertTrue(entry["capturedAt"].startswith("2015-01-02T03:04:05"))

    def test_missing_captured_at_omits_the_keys(self):
        entry = export.build_manifest_entry(make_record(captured_at=None), "a" * 64)
        self.assertNotIn("capturedAt", entry)
        self.assertNotIn("capturedOn", entry)

    def test_naive_captured_at_is_not_treated_as_utc(self):
        naive = datetime(2020, 6, 1, 12, 0, 0)
        entry = export.build_manifest_entry(make_record(captured_at=naive), "a" * 64)
        # Converted through local-time astimezone(), not misread as already-UTC.
        expected = naive.astimezone().astimezone(timezone.utc).isoformat()
        self.assertEqual(entry["capturedAt"], expected)

    def test_content_sha256_passthrough(self):
        entry = export.build_manifest_entry(make_record(), "f" * 64)
        self.assertEqual(entry["contentSha256"], "f" * 64)
        self.assertEqual(entry["sourceId"], "uuid-1")


class StateTests(unittest.TestCase):
    def test_load_state_missing_file_returns_empty_dict(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(export.load_state(Path(d) / "nope.json"), {})

    def test_load_state_corrupt_json_returns_empty_dict(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "state.json"
            path.write_text("{not json")
            self.assertEqual(export.load_state(path), {})

    def test_save_then_load_roundtrips(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "nested" / "state.json"
            state = {"uuid-1": {"signature": "1:2", "sha256": "a" * 64}}
            export.save_state(path, state)
            self.assertEqual(export.load_state(path), state)

    def test_save_state_leaves_no_tmp_file_behind(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "state.json"
            export.save_state(path, {"x": 1})
            self.assertEqual([p.name for p in Path(d).iterdir()], ["state.json"])


class NeedsConversionTests(unittest.TestCase):
    def test_true_when_no_cache_entry(self):
        self.assertTrue(export.needs_conversion(make_record(), {}))

    def test_false_when_signature_unchanged(self):
        record = make_record(file_size=1234, file_mtime_ns=1_000_000_000)
        state = {"uuid-1": {"signature": export.file_signature(1234, 1_000_000_000), "sha256": "a" * 64}}
        self.assertFalse(export.needs_conversion(record, state))

    def test_true_when_file_size_changed(self):
        record = make_record(file_size=9999, file_mtime_ns=1_000_000_000)
        state = {"uuid-1": {"signature": export.file_signature(1234, 1_000_000_000), "sha256": "a" * 64}}
        self.assertTrue(export.needs_conversion(record, state))

    def test_true_when_mtime_changed(self):
        record = make_record(file_size=1234, file_mtime_ns=2_000_000_000)
        state = {"uuid-1": {"signature": export.file_signature(1234, 1_000_000_000), "sha256": "a" * 64}}
        self.assertTrue(export.needs_conversion(record, state))


def _http_response(code, payload):
    body = json.dumps(payload).encode("utf-8") if payload is not None else b""
    resp = mock.MagicMock()
    resp.getcode.return_value = code
    resp.read.return_value = body
    resp.__enter__.return_value = resp
    resp.__exit__.return_value = False
    return resp


def _http_error(code, payload):
    import io

    body = json.dumps(payload).encode("utf-8") if payload is not None else b""
    return urllib.error.HTTPError(
        url="http://example.invalid", code=code, msg="err", hdrs=None, fp=io.BytesIO(body)
    )


class BackendClientTests(unittest.TestCase):
    def test_post_manifest_success(self):
        client = export.BackendClient("http://backend.invalid", "tok", retry_delays=())
        with mock.patch("urllib.request.urlopen", return_value=_http_response(200, {"ok": True, "results": []})):
            result = client.post_manifest([{"sourceId": "a"}])
        self.assertEqual(result, {"ok": True, "results": []})

    def test_request_sends_bearer_and_content_type_headers(self):
        client = export.BackendClient("http://backend.invalid", "secret-tok", retry_delays=())
        captured = {}

        def fake_urlopen(req, timeout=None):
            captured["auth"] = req.get_header("Authorization")
            captured["content_type"] = req.get_header("Content-type")
            return _http_response(200, {"ok": True, "results": []})

        with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
            client.post_manifest([])
        self.assertEqual(captured["auth"], "Bearer secret-tok")
        self.assertEqual(captured["content_type"], "application/json")

    def test_client_error_is_not_retried(self):
        client = export.BackendClient("http://backend.invalid", "tok", retry_delays=(0, 0, 0))
        calls = []

        def fake_urlopen(req, timeout=None):
            calls.append(1)
            raise _http_error(409, {"error": "sha256_mismatch"})

        with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
            with self.assertRaises(RuntimeError) as ctx:
                client.put_image("src", "a" * 64, b"jpeg-bytes")
        self.assertEqual(len(calls), 1, "a 4xx must not consume the retry budget")
        self.assertIn("409", str(ctx.exception))

    def test_server_error_is_retried_then_succeeds(self):
        client = export.BackendClient("http://backend.invalid", "tok", retry_delays=(0, 0))
        attempts = {"n": 0}

        def fake_urlopen(req, timeout=None):
            attempts["n"] += 1
            if attempts["n"] < 3:
                raise _http_error(503, {"error": "unavailable"})
            return _http_response(201, {"created": True, "photoId": "p1"})

        with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen), mock.patch("time.sleep"):
            result = client.put_image("src", "a" * 64, b"jpeg-bytes")
        self.assertEqual(attempts["n"], 3)
        self.assertEqual(result, {"created": True, "photoId": "p1"})

    def test_exhausted_retries_raises(self):
        client = export.BackendClient("http://backend.invalid", "tok", retry_delays=(0, 0))

        def fake_urlopen(req, timeout=None):
            raise _http_error(500, {"error": "boom"})

        with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen), mock.patch("time.sleep"):
            with self.assertRaises(RuntimeError):
                client.post_manifest([])

    def test_put_image_url_encodes_source_id(self):
        client = export.BackendClient("http://backend.invalid", "tok", retry_delays=())
        captured = {}

        def fake_urlopen(req, timeout=None):
            captured["url"] = req.full_url
            return _http_response(200, {"deduped": True})

        with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
            client.put_image("uuid/with slash", "b" * 64, b"data")
        self.assertIn("uuid%2Fwith%20slash", captured["url"])

    def test_non_2xx_success_code_from_manifest_raises(self):
        client = export.BackendClient("http://backend.invalid", "tok", retry_delays=())
        with mock.patch("urllib.request.urlopen", return_value=_http_response(202, {"weird": True})):
            with self.assertRaises(RuntimeError):
                client.post_manifest([])


class RunDryRunTests(unittest.TestCase):
    """Exercises `run()`'s orchestration without touching osxphotos/sips/network
    by monkeypatching the module-level Mac-specific functions."""

    def test_dry_run_never_calls_the_backend_and_persists_state(self):
        records = [make_record(source_id="uuid-1"), make_record(source_id="uuid-2", file_size=42)]

        with tempfile.TemporaryDirectory() as d:
            state_file = Path(d) / "state.json"
            args = argparse_namespace(
                album="Coffees",
                backend_url="http://backend.invalid",
                ingest_token="tok",
                state_file=str(state_file),
                limit=None,
                dry_run=True,
            )
            with mock.patch.object(export, "iter_album_photos", return_value=iter(records)), mock.patch.object(
                export, "convert_to_jpeg", return_value=b"fake-jpeg-bytes"
            ), mock.patch.object(export.BackendClient, "post_manifest") as post_manifest:
                rc = export.run(args)

            self.assertEqual(rc, 0)
            post_manifest.assert_not_called()
            state = export.load_state(state_file)
            self.assertEqual(set(state.keys()), {"uuid-1", "uuid-2"})
            self.assertEqual(state["uuid-1"]["sha256"], export.sha256_bytes(b"fake-jpeg-bytes"))

    def test_unchanged_photo_skips_conversion_on_second_run(self):
        record = make_record(source_id="uuid-1")

        with tempfile.TemporaryDirectory() as d:
            state_file = Path(d) / "state.json"
            args = argparse_namespace(
                album="Coffees",
                backend_url="http://backend.invalid",
                ingest_token="tok",
                state_file=str(state_file),
                limit=None,
                dry_run=True,
            )
            with mock.patch.object(export, "iter_album_photos", return_value=iter([record])), mock.patch.object(
                export, "convert_to_jpeg", return_value=b"fake-jpeg-bytes"
            ) as convert_first:
                export.run(args)
            convert_first.assert_called_once()

            with mock.patch.object(export, "iter_album_photos", return_value=iter([record])), mock.patch.object(
                export, "convert_to_jpeg"
            ) as convert_second:
                export.run(args)
            convert_second.assert_not_called()


def argparse_namespace(**kwargs):
    import argparse

    return argparse.Namespace(**kwargs)


if __name__ == "__main__":
    unittest.main()
