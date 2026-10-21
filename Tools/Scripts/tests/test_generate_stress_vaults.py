#!/usr/bin/env python3
"""Small deterministic fixture checks; generated output stays under .build/."""

import contextlib
import hashlib
import importlib.util
import io
import json
import re
import struct
import tempfile
import unittest
import zlib
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "stress_fixture", REPOSITORY / "Tools/Scripts/generate-stress-vaults.py")
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


class StressFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scratch = REPOSITORY / ".build/stress-generator-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="fixture-", dir=scratch)
        cls.root = Path(cls.temporary.name)
        with contextlib.redirect_stdout(io.StringIO()):
            cls.first = GENERATOR.generate(cls.root / "first", notes=512, images=12)
            cls.second = GENERATOR.generate(cls.root / "second", notes=512, images=12)
            cls.minimum = GENERATOR.generate(cls.root / "minimum", notes=500, images=1)

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def test_exact_repeatability_and_inventory(self):
        self.assertEqual(self.first, self.second)
        root = self.root / "first"
        actual = {path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file()}
        self.assertEqual(actual, set(self.first["files"]) | {"stress-manifest.json"})
        for path, entry in self.first["files"].items():
            source = (root / path).read_bytes()
            self.assertEqual(len(source), entry["bytes"], path)
            self.assertEqual(hashlib.sha256(source).hexdigest(), entry["sha256"], path)
        self.assertEqual(self.first["counts"]["notes"], 512)
        self.assertEqual(self.minimum["counts"]["notes"], 500)
        self.assertFalse(self.minimum["scenarios"])
        self.assertEqual(sum(self.first["notes_by_role"].values()), 512)

    def test_standard_baseline_is_byte_identical(self):
        baseline = json.loads((self.root / "minimum/fixture-manifest.json").read_text())
        self.assertEqual(baseline, json.loads((self.root / "first/fixture-manifest.json").read_text()))
        for path, expected in baseline["files_sha256"].items():
            self.assertEqual(self.first["files"][path]["sha256"], expected, path)
        self.assertFalse(any(".scholium" in Path(path).parts for path in self.first["files"]))

    def test_full_advertised_corpus_paths_are_unique(self):
        paths = [GENERATOR.corpus_path(index) for index in range(1, 20001)]
        self.assertEqual(len(set(paths)), len(paths))
        deep = "Stress Corpus/Deep/一/Two/三/Four/五/Six/七/Eight"
        self.assertEqual(GENERATOR.corpus_path(1961), f"02-topics/{deep}/Stress Duplicate.md")
        self.assertEqual(GENERATOR.corpus_path(3922), f"01-analyses/{deep}/Stress Duplicate.md")
        self.assertEqual(GENERATOR.corpus_path(5883), f"03-works/{deep}/Stress Duplicate.md")
        self.assertNotEqual(GENERATOR.corpus_path(7844), GENERATOR.corpus_path(1961))
        self.assertEqual(Path(GENERATOR.corpus_path(7844)).stem, "Stress Duplicate")

    def test_search_oracles_match_independent_authored_markers(self):
        root = self.root / "first"
        sources = {path: (root / path).read_bytes() for path in self.first["files"]
                   if path.split("/")[0] in GENERATOR.ROLES and path.endswith(".md")}
        oracles = {item["label"]: item for item in self.first["search_oracles"]}
        body_matches = [path for path, data in sources.items() if b"stress-token-000001" in data]
        self.assertEqual(body_matches, oracles["rare_body"]["expected_paths"])
        self.assertEqual([path for path in sources if Path(path).stem == "Stress Long Prose"],
                         oracles["rare_title"]["expected_paths"])
        markers = {"broad_keyword": b"keywords: [stress-fixture,",
                   "broad_property": b"fixture_only: true",
                   "broad_cjk_body": "全部内容为合成测试材料".encode("utf-8")}
        for label, marker in markers.items():
            self.assertEqual(sum(marker in source for source in sources.values()),
                             oracles[label]["expected_count"], label)
        self.assertTrue(all(b"scholium-stress-no-result-9f4e7dca" not in source for source in sources.values()))
        self.assertTrue(all(b"stressabsentquery" not in source for source in sources.values()))
        self.assertTrue(all(item["expected_count"] == 0 for item in self.minimum["search_oracles"]))
        eight = {item["label"]: item for item in GENERATOR.search_oracles(508)}
        self.assertNotIn("rare_body", eight)
        self.assertEqual(eight["rare_title"]["expected_count"], 1)
        self.assertEqual(eight["broad_cjk_body"]["expected_count"], 8)

    def test_scenario_boundaries_and_source_fidelity(self):
        root = self.root / "first"
        scenarios = self.first["scenarios"]
        self.assertEqual(set(scenarios), set(GENERATOR.SCENARIO_PATHS))
        self.assertEqual((root / scenarios["long_prose"]).stat().st_size, 512 * 1024)
        self.assertEqual((root / scenarios["near_source_limit"]).stat().st_size,
                         GENERATOR.MAXIMUM_NOTE_BYTES - 1024)
        swift = (REPOSITORY / "ScholiumContracts/VaultSourceReadLimits.swift").read_text()
        expression = re.search(r"maximumNoteByteCount\s*=\s*([\d_* ]+)", swift).group(1)
        # The SDK-facing owner currently expresses its constant as integer factors.
        supported = 1
        for factor in expression.split("*"):
            supported *= int(factor.strip().replace("_", ""))
        self.assertEqual(GENERATOR.MAXIMUM_NOTE_BYTES, supported)
        source = (root / scenarios["source_fidelity"]).read_bytes()
        self.assertTrue(source.startswith(b"\xef\xbb\xbf"))
        self.assertIn(b"\r\n", source)
        self.assertNotIn(b"\n", source.replace(b"\r\n", b""))
        self.assertFalse(source.endswith(b"\n"))
        self.assertGreater(self.first["counts"]["wikilink_occurrences"], 9000)
        self.assertGreater(self.first["counts"]["callout_markers"], 1500)

    def test_distinct_local_images_have_bounded_decoded_dimensions(self):
        image_paths = sorted((self.root / "first/02-topics/Attachments/stress").glob("*.png"))
        self.assertEqual(len(image_paths), 12 + GENERATOR.LARGE_IMAGE_COUNT)
        self.assertEqual(len({hashlib.sha256(path.read_bytes()).digest() for path in image_paths}), len(image_paths))
        for path in image_paths:
            data = path.read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            dimensions = GENERATOR.LARGE_IMAGE_SIZE if "large" in path.name else GENERATOR.IMAGE_SIZE
            self.assertEqual(struct.unpack("!II", data[16:24]), dimensions)
            position = 8
            compressed = bytearray()
            while position < len(data):
                size = struct.unpack("!I", data[position:position + 4])[0]
                kind = data[position + 4:position + 8]
                payload = data[position + 8:position + 8 + size]
                checksum = struct.unpack("!I", data[position + 8 + size:position + 12 + size])[0]
                self.assertEqual(zlib.crc32(kind + payload), checksum)
                if kind == b"IDAT":
                    compressed.extend(payload)
                position += size + 12
            width, height = dimensions
            self.assertEqual(len(zlib.decompress(compressed)), height * (1 + width * 3))
        self.assertNotEqual(GENERATOR.png(0), GENERATOR.png(256))

    def test_format_matrix_combines_dense_syntax_in_one_document(self):
        path = self.first["scenarios"]["format_matrix"]
        source = (self.root / "first" / path).read_text()
        # Authored construction counts, independent of the application parser.
        self.assertEqual(source.count("### Format block "), 120)
        self.assertEqual(source.count("```mermaid\n"), 120)
        self.assertEqual(source.count("```text\n"), 120)
        self.assertEqual(source.count("> [!state] Mixed Callout "), 120)
        self.assertEqual(source.count("> > [!flag] Nested"), 120)
        self.assertEqual(source.count("{{Synthetic annotation "), 120)
        self.assertEqual(source.count("[[Stress Missing Matrix "), 120)
        self.assertEqual(source.count("`inline [[literal]]`"), 120)
        self.assertEqual(source.count("\\*escaped\\*"), 120)
        dense = (self.root / "first" / self.first["scenarios"]["dense_links"]).read_text()
        self.assertEqual(dense.count("{{Synthetic navigation annotation "), 2400)
        callouts = (self.root / "first" / self.first["scenarios"]["nested_callouts"]).read_text()
        for kind in ("orient", "cite", "connect", "state", "illustrate", "quote", "flag", "NOTE"):
            self.assertIn(f"[!{kind}]", callouts)

    def test_existing_directory_and_symlink_are_refused_without_changes(self):
        root = self.root / "first"
        before = (root / "stress-manifest.json").read_bytes()
        with self.assertRaises(ValueError):
            GENERATOR.generate(root, notes=512, images=1)
        self.assertEqual((root / "stress-manifest.json").read_bytes(), before)
        dangling = self.root / "dangling"
        dangling.symlink_to(self.root / "absent")
        with self.assertRaises(ValueError):
            GENERATOR.generate(dangling, notes=500, images=1)
        self.assertTrue(dangling.is_symlink())
        for count in (499, 20001):
            destination = self.root / f"refuse-{count}"
            with self.assertRaises(ValueError):
                GENERATOR.generate(destination, notes=count)
            self.assertFalse(destination.exists())


if __name__ == "__main__":
    unittest.main()
