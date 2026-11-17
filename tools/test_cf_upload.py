"""Offline tests for cf_upload.py (no network, no key): python3 -I tools/test_cf_upload.py"""
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cf_upload  # noqa: E402


class Resp:
    def __init__(self, payload):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self, *a):
        return json.dumps(self.payload).encode()


class CfUploadTest(unittest.TestCase):
    VERSIONS = [
        {"id": 1, "name": "1.60.1", "gameVersionTypeID": 517},  # a retail version of the same name is ignored
        {"id": 2, "name": "1.60.1", "gameVersionTypeID": cf_upload.FOREVER_TYPE},
    ]

    def test_picks_the_forever_version(self):
        self.assertEqual(cf_upload.version_id(self.VERSIONS), 2)

    def test_missing_version_stops(self):
        with self.assertRaises(SystemExit):
            cf_upload.version_id(self.VERSIONS[:1])

    def test_prerelease_is_beta_and_empty_notes_stop(self):
        meta = cf_upload.metadata({"tag_name": "v0.2.0-rc.1", "body": "notes", "prerelease": True}, 2)
        self.assertEqual((meta["releaseType"], meta["displayName"], meta["gameVersions"]), ("beta", "v0.2.0-rc.1", [2]))
        with self.assertRaises(SystemExit):
            cf_upload.metadata({"tag_name": "v1", "body": "  "}, 2)

    def test_upload_posts_to_our_project(self):
        calls = []

        def opener(req, timeout):
            calls.append(req)
            return Resp(self.VERSIONS if req.get_method() == "GET" else {"id": 99})

        path = os.path.join(os.path.dirname(__file__), "test_cf_upload.py")  # any file stands in for the zip
        meta, result = cf_upload.upload({"tag_name": "v0.1.0", "body": "notes"}, path, "token", opener)
        self.assertEqual(result["id"], 99)
        self.assertTrue(calls[1].full_url.endswith("/projects/1812424/upload-file"))
        self.assertEqual(meta["releaseType"], "release")


if __name__ == "__main__":
    unittest.main()
