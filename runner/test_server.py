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


if __name__ == "__main__":
    unittest.main()
