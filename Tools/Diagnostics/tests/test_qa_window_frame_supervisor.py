"""Admission and receipt safety; no recorder, process, or QA launch."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
import uuid


SOURCE = Path(__file__).resolve().parents[1] / "qa_window_frame_supervisor.py"
SPEC = importlib.util.spec_from_file_location("qa_window_frame_supervisor", SOURCE)
supervisor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(supervisor)


class CaptureAdmissionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="frame-supervisor-test-", dir=supervisor.BUILD)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.request = self.root / f"{uuid.uuid4()}.request.json"
        self.output = self.root / "frames"
        self.payload = {"schema": 1, "pid": 43210, "output": str(self.output)}
        self.qa_executable = supervisor.BUILD / "qa-runtime/Scholium-QA.app/Contents/MacOS/Scholium"

    def pid_reader(self, executable=None):
        encoded = str(executable or self.qa_executable).encode()

        def fill(_pid, buffer, _size):
            buffer.value = encoded
            return len(encoded)

        return Mock(side_effect=fill)

    def write(self, payload=None):
        self.request.write_text(json.dumps(self.payload if payload is None else payload), encoding="utf-8")

    def test_valid_request_has_a_working_admission_oracle(self):
        self.write()
        reader = self.pid_reader()
        self.assertEqual(supervisor.read_request(self.request, reader), (43210, self.output))
        reader.assert_called_once()
        self.assertFalse(self.output.exists(), "Admission must leave directory creation to the helper.")

    def test_unknown_duplicate_and_coerced_schema_keys_never_reach_pid_lookup(self):
        cases = [
            json.dumps(dict(self.payload, source="synthetic forbidden source")),
            '{"schema":1,"schema":1,"pid":43210,"output":' + json.dumps(str(self.output)) + '}',
            json.dumps(dict(self.payload, schema=True)),
            json.dumps(dict(self.payload, pid=True)),
        ]
        for raw in cases:
            with self.subTest(raw=raw):
                self.request.write_text(raw, encoding="utf-8")
                reader = self.pid_reader()
                with self.assertRaises(ValueError):
                    supervisor.read_request(self.request, reader)
                reader.assert_not_called()
        self.assertFalse(self.output.exists())

    def test_oversized_otherwise_valid_json_is_rejected_before_pid_lookup(self):
        self.request.write_bytes(json.dumps(self.payload).encode() + b" " * 4097)
        reader = self.pid_reader()
        with self.assertRaisesRegex(ValueError, "request too large"):
            supervisor.read_request(self.request, reader)
        reader.assert_not_called()

    def test_symlink_request_and_symlink_output_parent_are_rejected(self):
        real_request = self.root / "real-request.json"
        real_request.write_text(json.dumps(self.payload), encoding="utf-8")
        self.request.symlink_to(real_request)
        reader = self.pid_reader()
        with self.assertRaises(ValueError):
            supervisor.read_request(self.request, reader)
        reader.assert_not_called()
        self.request.unlink()

        real_parent = self.root / "real-parent"
        real_parent.mkdir()
        alias = self.root / "alias"
        alias.symlink_to(real_parent, target_is_directory=True)
        self.write(dict(self.payload, output=str(alias / "frames")))
        with self.assertRaises(ValueError):
            supervisor.read_request(self.request, reader)
        reader.assert_not_called()
        self.assertEqual(list(real_parent.iterdir()), [])

    def test_external_existing_and_symlink_output_leaves_are_rejected(self):
        # Only reference this absent path; all fixtures and writes remain in .build.
        outside = supervisor.REPOSITORY / f"frame-supervisor-forbidden-{uuid.uuid4()}"
        self.output.mkdir()
        sentinel = self.output / "preserve"
        sentinel.write_bytes(b"unchanged")
        alias = self.root / "dangling-output"
        alias.symlink_to(outside, target_is_directory=True)
        for output in [outside, self.output, alias]:
            with self.subTest(output=str(output)):
                self.write(dict(self.payload, output=str(output)))
                reader = self.pid_reader()
                with self.assertRaises(ValueError):
                    supervisor.read_request(self.request, reader)
                reader.assert_not_called()
        self.assertFalse(outside.exists())
        self.assertEqual(sentinel.read_bytes(), b"unchanged")
        self.assertTrue(alias.is_symlink())

    def test_non_qa_executable_pid_cannot_be_admitted(self):
        self.write()
        reader = self.pid_reader(Path("/Applications/Unrelated.app/Contents/MacOS/Unrelated"))
        with self.assertRaisesRegex(ValueError, "QA executable"):
            supervisor.read_request(self.request, reader)
        reader.assert_called_once()
        self.assertFalse(self.output.exists())


class CompletionReceiptTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="frame-receipt-test-", dir=supervisor.BUILD)
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.identifier = str(uuid.uuid4()).upper()
        self.receipt = self.root / f"{self.identifier}.finished.json"

    def test_complete_receipt_is_published_once_without_temporary_files(self):
        supervisor.finished(self.root, self.identifier, 77)
        self.assertEqual(json.loads(self.receipt.read_text()), {"exit_code": 77})
        original = self.receipt.read_bytes()
        with self.assertRaises(FileExistsError):
            supervisor.finished(self.root, self.identifier, 0)
        self.assertEqual(self.receipt.read_bytes(), original)
        self.assertEqual(set(self.root.iterdir()), {self.receipt})

    def test_symlink_receipt_preserves_both_link_and_target(self):
        target = self.root / "preserved-target"
        target.write_bytes(b"must not be replaced")
        self.receipt.symlink_to(target)
        with self.assertRaises(FileExistsError):
            supervisor.finished(self.root, self.identifier, 0)
        self.assertTrue(self.receipt.is_symlink())
        self.assertEqual(target.read_bytes(), b"must not be replaced")
        self.assertEqual(set(self.root.iterdir()), {self.receipt, target})


if __name__ == "__main__":
    unittest.main()
