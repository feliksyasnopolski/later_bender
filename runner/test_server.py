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

    def test_stream_chunks_are_bounded_and_resumable(self):
        with tempfile.TemporaryDirectory() as directory:
            data = ("abcdefgh" * 4100).encode()
            Path(directory, "stdout").write_bytes(data)
            row = {"handle": "WSE-chunks", "output_dir": directory, "state": "exited"}
            chunks = []
            cursor = None
            while True:
                result = server.stream(row, "stdout", cursor, "text")
                chunks.append(result["data"])
                cursor = result["next_cursor"]
                if cursor is None:
                    self.assertTrue(result["stream_complete"])
                    break
                self.assertFalse(result["stream_complete"])
                self.assertLessEqual(result["chunk_byte_size"], 16 * 1024)
            self.assertEqual(data.decode(), "".join(chunks))
            self.assertEqual([16 * 1024, 16 * 1024, len(data) - 32 * 1024], [len(chunk.encode()) for chunk in chunks])

    def test_stream_waits_for_short_output_burst_to_settle(self):
        import threading
        import time
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "stdout")
            row = {"handle": "WSE-settle", "output_dir": directory, "state": "running"}
            def write_burst():
                time.sleep(0.05)
                path.write_bytes(b"echo\n")
                time.sleep(0.05)
                path.write_bytes(b"echo\nresult\n")
            writer = threading.Thread(target=write_burst)
            writer.start()
            result = server.stream(row, "stdout", "0", "text", wait_seconds=1)
            writer.join()
            self.assertEqual("echo\nresult\n", result["data"])
            self.assertEqual(len(b"echo\nresult\n"), result["chunk_byte_size"])
            self.assertEqual(str(len(b"echo\nresult\n")), result["next_cursor"])

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

    def test_pty_execution_keeps_stdin_open_and_uses_docker_tty(self):
        from unittest.mock import Mock, patch
        with tempfile.TemporaryDirectory() as directory:
            process = Mock()
            process.stdin = Mock()
            process.wait.return_value = 0
            process.poll.return_value = None
            row = {"handle": "WSE-pty-test", "output_dir": directory}
            payload = {"command": "python3 -i", "pty": True, "cwd": "/workspace", "stdin": "print(2)\n"}
            with patch.object(server.subprocess, "Popen", return_value=process) as spawn:
                server.start_execution(row, payload, "WSR-test")
                args, kwargs = spawn.call_args
                self.assertEqual("docker", args[0][0])
                self.assertIn("-i", args[0])
                self.assertIn("-t", args[0])
                self.assertEqual("WSR-test", args[0][args[0].index("-w") + 2])
                self.assertIsNotNone(kwargs["stdin"])
                process.stdin.write.assert_called_once_with(b"print(2)\n")
                process.stdin.flush.assert_called_once()


if __name__ == "__main__":
    unittest.main()
