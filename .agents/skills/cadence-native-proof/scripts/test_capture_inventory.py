import base64
import hashlib
from pathlib import Path
import tempfile
import unittest

from capture_inventory import inventory

# Synthetic 1x1 PNG, never presented as native capture evidence.
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a0mUAAAAASUVORK5CYII=")
SHA = "a" * 40


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "capture.png").write_bytes(PNG)

    def test_exact_bytes_and_declared_provenance(self):
        result = inventory(self.root, ["capture.png"], SHA, "mockup")
        self.assertEqual(result["files"], [{"path": "capture.png", "bytes": len(PNG),
                                         "sha256": hashlib.sha256(PNG).hexdigest()}])
        self.assertEqual(result["source_sha"], SHA)
        self.assertEqual(result["declared_platform"], "mockup")

    def test_requires_complete_sha_platform_and_files(self):
        for sha, platform, names in [("abc123", "native", ["capture.png"]),
                                     (SHA, "unknown", ["capture.png"]), (SHA, "native", [])]:
            with self.subTest(sha=sha, platform=platform, names=names):
                with self.assertRaises(ValueError):
                    inventory(self.root, names, sha, platform)

    def test_missing_and_non_png_files_fail(self):
        with self.assertRaises(FileNotFoundError):
            inventory(self.root, ["missing.png"], SHA, "native")
        for data in (b"not an image", b"\x89PNG\r\n\x1a\n"):
            (self.root / "bad.png").write_bytes(data)
            with self.assertRaises(ValueError):
                inventory(self.root, ["bad.png"], SHA, "native")

    def test_duplicate_and_path_escape_fail(self):
        for names in (["capture.png", "./capture.png"], ["../capture.png"],
                      [str(self.root / "capture.png")]):
            with self.subTest(names=names):
                with self.assertRaises(ValueError):
                    inventory(self.root, names, SHA, "native")

    def test_symlink_outside_root_fails(self):
        with tempfile.TemporaryDirectory() as other:
            outside = Path(other) / "outside.png"
            outside.write_bytes(PNG)
            (self.root / "link.png").symlink_to(outside)
            with self.assertRaises(ValueError):
                inventory(self.root, ["link.png"], SHA, "native")

    def test_changed_bytes_change_hash(self):
        before = inventory(self.root, ["capture.png"], SHA, "web")
        (self.root / "capture.png").write_bytes(PNG + b"changed")
        after = inventory(self.root, ["capture.png"], SHA, "web")
        self.assertNotEqual(before["files"][0]["sha256"], after["files"][0]["sha256"])


if __name__ == "__main__":
    unittest.main()
