import base64
import json
import tempfile
import unittest
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import server


class RunnerUnitTest(unittest.TestCase):
    def test_limits_reject_requirements_above_offering(self):
        old = server.os.environ.get("WORKSPACE_DEFAULT_PIDS")
        server.os.environ["WORKSPACE_DEFAULT_PIDS"] = "4"
        try:
            with self.assertRaisesRegex(ValueError, "workspace_quota_exceeded"):
                server.limits({"resources": {"min_pids": 5}})
        finally:
            if old is None:
                server.os.environ.pop("WORKSPACE_DEFAULT_PIDS", None)
            else:
                server.os.environ["WORKSPACE_DEFAULT_PIDS"] = old

    def test_stream_preserves_binary_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "stdout").write_bytes(b"a\x00b")
            row = {"handle": "WSE-test", "output_dir": directory, "state": "exited"}
            result = server.stream(row, "stdout", None, "auto")
            self.assertEqual("base64", result["format"])
            self.assertEqual(b"a\x00b", base64.b64decode(result["data"]))
            self.assertEqual(3, result["total_byte_size"])
            self.assertTrue(result["stream_complete"])

    def test_auto_uses_base64_for_invalid_utf8_without_nul(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            data = b"\xffABC"
            (output / "stdout").write_bytes(data)
            row = {"handle": "WSE-test", "output_dir": directory, "state": "exited"}
            result = server.stream(row, "stdout", None, "auto")
            self.assertEqual("base64", result["format"])
            self.assertEqual("/0FCQw==", result["data"])
            self.assertEqual(len(data), result["chunk_byte_size"])

    def test_auto_keeps_valid_utf8_as_text(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            (output / "stdout").write_bytes("héllo".encode())
            row = {"handle": "WSE-test", "output_dir": directory, "state": "exited"}
            result = server.stream(row, "stdout", None, "auto")
            self.assertEqual("text", result["format"])
            self.assertEqual("héllo", result["data"])

    def test_binary_promotion_uses_octet_stream_for_unknown_bytes(self):
        self.assertEqual("application/octet-stream", server.media_type_for("artifact.bin", b"\x00\x01\xffABC"))
        self.assertEqual("text/plain", server.media_type_for("artifact.txt", b"plain text"))


if __name__ == "__main__":
    unittest.main()
