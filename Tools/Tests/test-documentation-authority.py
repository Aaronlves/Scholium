#!/usr/bin/env python3
"""Exercise document-boundary rejection with disposable repository-local files."""

from contextlib import redirect_stderr
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "documentation_authority", ROOT / "Tools/Scripts/validate-documentation-authority.py"
)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class DocumentationAuthorityTests(unittest.TestCase):
    def setUp(self):
        scratch = ROOT / ".build/documentation-authority-tests"
        scratch.mkdir(parents=True, exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "Design.md"
        self.charter = (ROOT / "Design.md").read_text(encoding="utf-8")

    def check_design(self, source):
        self.path.write_text(source, encoding="utf-8")
        validator.validate_design_document(self.path)

    def assert_rejected(self, source, reason):
        diagnostics = io.StringIO()
        with redirect_stderr(diagnostics), self.assertRaises(SystemExit):
            self.check_design(source)
        self.assertIn(reason, diagnostics.getvalue())

    def test_current_charter_passes(self):
        self.check_design(self.charter)

    def test_global_prose_revision_passes(self):
        self.check_design(self.charter.replace("quiet reading", "calm reading"))

    def test_feature_appendix_is_rejected(self):
        self.assert_rejected(self.charter + "\n## Chat composer\n", "section set")

    def test_detailed_subheading_is_rejected(self):
        self.assert_rejected(self.charter + "\n#### Button defaults\n", "section set")

    def test_component_table_is_rejected(self):
        self.assert_rejected(self.charter + "\n| Control | Recipe |\n", "tables")

    def test_code_recipe_is_rejected(self):
        self.assert_rejected(self.charter + "\n```swift\nbutton.tint(color)\n```\n", "code")

    def test_local_metrics_are_rejected(self):
        for recipe in ("Rows are 28pt.", "Opacity is 30%.", "Fade takes 200 ms."):
            with self.subTest(recipe=recipe):
                self.assert_rejected(self.charter + "\n" + recipe, "recipes")

    def test_prose_growth_without_new_sections_is_rejected(self):
        self.assert_rejected(self.charter + " detail" * 1101, "budget")

    def test_line_growth_is_rejected(self):
        self.assert_rejected(self.charter + "\n" * 141, "budget")

    def test_copied_rule_is_rejected_across_owners(self):
        rule = " ".join(f"word{index}" for index in range(40))
        peer = self.path.with_name("Workflow.md")
        self.path.write_text(rule, encoding="utf-8")
        peer.write_text(rule.replace(" ", "\n", 10), encoding="utf-8")
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            validator.validate_unique_specification_paragraphs([self.path, peer])

    def test_distinct_rules_and_short_links_pass(self):
        peer = self.path.with_name("Workflow.md")
        self.path.write_text("See the owning workflow.\n\n" + "one " * 40, encoding="utf-8")
        peer.write_text("See the owning workflow.\n\n" + "two " * 40, encoding="utf-8")
        validator.validate_unique_specification_paragraphs([self.path, peer])


if __name__ == "__main__":
    unittest.main()
