"""Synthetic pixels check that toolbar changes cannot stand in for document paint."""
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[3]
BINARY = os.environ.get('SCHOLIUM_QA_MODE_FRAME_COMPARATOR')


def write_png(path, width, height, pixels):
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    rows = b''.join(b'\0' + bytes(pixels[y * width * 3:(y + 1) * width * 3]) for y in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def pixels(mode, body):
    width = height = 200
    image = bytearray([255] * (width * height * 3))
    def rectangle(x, y, w, h):
        for row in range(y, y + h):
            for col in range(x, x + w):
                offset = (row * width + col) * 3
                image[offset:offset + 3] = b'\x12\x12\x12'
    rectangle(132 if mode == 'before' else 151, 7, 13, 12)
    if body != 'blank':
        for y in range(55, 185, 7):
            rectangle(29 if body == 'before' else 49, y, 105, 3)
    return image


@unittest.skipUnless(BINARY, 'Set SCHOLIUM_QA_MODE_FRAME_COMPARATOR to the compiled diagnostic helper.')
class ModeFrameComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='mode-frame-proof-', dir=ROOT / '.build')
        self.directory = Path(self.temporary.name)
        self.frames = self.directory / 'frames'
        self.frames.mkdir()
        observation = {
            'kind': 'mode_switch', 'origin': 'Edit', 'mode': 'Source',
            'driver_action_start_uptime_ns': 125_000_000,
            'passive_interval_end_uptime_ns': 400_000_000,
            'mode_control_crop_top_left_normalized': {'x': .65, 'y': .02, 'width': .2, 'height': .1},
            'body_crop_top_left_normalized': {'x': .1, 'y': .2, 'width': .85, 'height': .75},
        }
        (self.directory / 'observations.json').write_text(json.dumps(observation))
        (self.frames / 'capture-summary.json').write_text(json.dumps({'errors': 0, 'overflow_frames': 0}))

    def tearDown(self):
        self.temporary.cleanup()

    def capture(self, states):
        records = []
        for index, (mode, body) in enumerate(states):
            name = f'frame-{index:05d}.png'
            write_png(self.frames / name, 200, 200, pixels(mode, body))
            records.append({'file': name, 'display_uptime_ns': (100 + index * 50) * 1_000_000})
        (self.frames / 'frames.jsonl').write_text(''.join(json.dumps(r) + '\n' for r in records))
        return subprocess.run([BINARY, str(self.directory)], capture_output=True, text=True)

    def test_changed_mode_with_old_or_blank_body_does_not_complete_display(self):
        result = self.capture([('before', 'before'), ('after', 'before'), ('after', 'blank'),
                               ('after', 'after'), ('after', 'after')])
        self.assertEqual(result.returncode, 0, result.stderr[-1000:])
        report = json.loads((self.directory / 'mode-frame-comparison.json').read_text())
        self.assertEqual(report['first_matching_frame'], 'frame-00003.png')
        self.assertFalse(report['frames'][1]['mode_and_body_match'])
        self.assertFalse(report['frames'][2]['mode_and_body_match'])
        self.assertTrue(report['body_has_discriminating_visual_change'])

    def test_missing_mode_indicator_change_invalidates_measurement(self):
        result = self.capture([('before', 'before'), ('before', 'after'), ('before', 'after')])
        self.assertNotEqual(result.returncode, 0)

    def test_visually_unchanged_body_is_explicit_in_result(self):
        result = self.capture([('before', 'after'), ('after', 'after'), ('after', 'after')])
        self.assertEqual(result.returncode, 0, result.stderr[-1000:])
        report = json.loads((self.directory / 'mode-frame-comparison.json').read_text())
        self.assertFalse(report['body_has_discriminating_visual_change'])

    def test_capture_overflow_invalidates_measurement(self):
        (self.frames / 'capture-summary.json').write_text(json.dumps({'errors': 0, 'overflow_frames': 1}))
        result = self.capture([('before', 'before'), ('after', 'after'), ('after', 'after')])
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
