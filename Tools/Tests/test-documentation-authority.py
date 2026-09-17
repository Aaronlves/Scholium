#!/usr/bin/env python3
"""Exercise document-boundary rejection with disposable repository-local files."""

from contextlib import redirect_stderr
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


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
            validator.validate_unique_paragraphs([self.path, peer])

    def test_distinct_rules_and_short_links_pass(self):
        peer = self.path.with_name("Workflow.md")
        self.path.write_text("See the owning workflow.\n\n" + "one " * 40, encoding="utf-8")
        peer.write_text("See the owning workflow.\n\n" + "two " * 40, encoding="utf-8")
        validator.validate_unique_paragraphs([self.path, peer])

    def test_collection_budget_accepts_exact_limit(self):
        peer = self.path.with_name("Peer.md")
        self.path.write_text("one " * 4, encoding="utf-8")
        peer.write_text("two " * 5, encoding="utf-8")
        self.assertEqual(validator.validate_collection_budget(
            "Architecture", [self.path, peer], 9), 9)

    def test_splitting_files_cannot_evade_collection_budget(self):
        peer = self.path.with_name("Peer.md")
        self.path.write_text("one " * 6, encoding="utf-8")
        peer.write_text("two " * 6, encoding="utf-8")
        diagnostics = io.StringIO()
        with redirect_stderr(diagnostics), self.assertRaises(SystemExit):
            validator.validate_collection_budget("Architecture", [self.path, peer], 10)
        self.assertIn("collection has 12 words", diagnostics.getvalue())

    def test_budget_counts_code_and_new_nested_documents(self):
        nested = self.path.parent / "chapters" / "Nested.md"
        nested.parent.mkdir()
        self.path.write_text("```\n" + "code " * 6 + "\n```", encoding="utf-8")
        nested.write_text("detail " * 6, encoding="utf-8")
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            validator.validate_collection_budget(
                "Status", list(self.path.parent.rglob("*.md")), 10)

    def test_developer_budget_discovers_guidance_outside_known_reference_folders(self):
        root = self.path.parent
        (root / "AGENTS.md").write_text("repository rules", encoding="utf-8")
        skill = root / ".agents" / "skills" / "example"
        guide = skill / "new-folder" / "Guide.md"
        guide.parent.mkdir(parents=True)
        (skill / "SKILL.md").write_text("skill entry", encoding="utf-8")
        guide.write_text("additional guidance", encoding="utf-8")
        paths = validator.developer_instruction_paths(root)
        self.assertEqual(set(paths), {root / "AGENTS.md", skill / "SKILL.md", guide})

    def test_external_hig_corpus_is_excluded_but_its_procedure_is_counted(self):
        root = self.path.parent
        (root / "AGENTS.md").write_text("repository rules", encoding="utf-8")
        hig = root / ".agents" / "skills" / "apple-hig"
        for relative in ("sources/snapshot.md", "distilled/topic.md",
                         "routing-index.md", "process.md", "SKILL.md"):
            file = hig / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("reference words", encoding="utf-8")
        self.assertEqual(set(validator.developer_instruction_paths(root)), {
            root / "AGENTS.md", hig / "process.md", hig / "SKILL.md",
        })

    def test_other_skills_cannot_claim_the_hig_source_exclusion(self):
        root = self.path.parent
        (root / "AGENTS.md").write_text("repository rules", encoding="utf-8")
        guide = root / ".agents" / "skills" / "other" / "sources" / "Guide.md"
        guide.parent.mkdir(parents=True)
        guide.write_text("maintained instructions", encoding="utf-8")
        self.assertIn(guide, validator.developer_instruction_paths(root))

    def test_copied_rule_is_rejected_between_architecture_and_developer_guidance(self):
        peer = self.path.with_name("SKILL.md")
        rule = " ".join(f"rule{index}" for index in range(40))
        self.path.write_text(rule, encoding="utf-8")
        peer.write_text(rule, encoding="utf-8")
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            validator.validate_unique_paragraphs([self.path, peer])

    def test_duplicate_code_examples_and_short_safety_reminders_pass(self):
        peer = self.path.with_name("SKILL.md")
        example = "\n\n".join("code " * 40 for _ in range(2))
        for fence in ("```", "~~~~"):
            with self.subTest(fence=fence):
                source = f"Keep exact source.\n\n{fence}text\n{example}\n{fence}\n"
                self.path.write_text(source, encoding="utf-8")
                peer.write_text(source, encoding="utf-8")
                validator.validate_unique_paragraphs([self.path, peer])

    def test_copied_prose_after_code_example_is_still_rejected(self):
        peer = self.path.with_name("SKILL.md")
        source = "```text\nexample\n````\n\n" + "rule " * 40
        self.path.write_text(source, encoding="utf-8")
        peer.write_text(source, encoding="utf-8")
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            validator.validate_unique_paragraphs([self.path, peer])

    def test_indented_literal_fence_does_not_hide_following_prose(self):
        peer = self.path.with_name("SKILL.md")
        source = "    ```text\n\n" + "rule " * 40
        self.path.write_text(source, encoding="utf-8")
        peer.write_text(source, encoding="utf-8")
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            validator.validate_unique_paragraphs([self.path, peer])

    def test_duplicate_indented_code_examples_pass(self):
        peer = self.path.with_name("SKILL.md")
        source = "    " + "code " * 40 + "\n"
        self.path.write_text(source, encoding="utf-8")
        peer.write_text(source, encoding="utf-8")
        validator.validate_unique_paragraphs([self.path, peer])

    def test_main_rejects_copied_prose_in_new_nested_architecture_document(self):
        root = self.path.parent

        def write(relative, source):
            file = root / relative
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(source, encoding="utf-8")

        write("AGENTS.md", "# Rules\n\n## Design document change boundary\n")
        write("Design.md", self.charter)
        write("README.md", "# Project\n")
        write("README.zh-Hans.md", "# Project\n")
        write("Docs/SCHOLIUM_SPEC.md", "# Specification\n\n"
              "[Foundation](Specification/Foundation.md)\n"
              "[Design](../Design.md)\n"
              "[Accessibility](Specification/Accessibility.md)\n"
              "[Release](Specification/Release.md)\n")
        backlink = "[SCHOLIUM_SPEC.md](../SCHOLIUM_SPEC.md)\n\n"
        write("Docs/Specification/Foundation.md", "# Foundation\n\n" + backlink
              + "\n".join(f"## {number}. Contract" for number in range(1, 19))
              + "\n" + "\n".join(f"### 18.{number} Interface" for number in range(1, 8))
              + "\n## Appendix A. Source\n")
        write("Docs/Specification/Accessibility.md", "# Accessibility\n\n"
              + backlink + "## 20. Accessibility\n")
        write("Docs/Specification/Release.md", "# Release\n\n" + backlink
              + "## 21. Release\n\n## 22. Decisions\n")
        rule = " ".join(f"rule{index}" for index in range(40))
        for manifest, directory in (("IMPLEMENTATION_ARCHITECTURE.md", "Architecture"),
                                    ("IMPLEMENTATION_STATUS.md", "Status")):
            write(f"Docs/{manifest}", f"# Manifest\n\n[Owner]({directory}/Owner.md)\n")
            write(f"Docs/{directory}/Owner.md", "# Owner\n\n"
                  + f"[{manifest}](../{manifest})\n\n"
                  + (rule if directory == "Architecture" else "Current evidence."))
        write("Docs/Architecture/nested/Extra.md", "# Extra\n\n" + rule)
        manifests = tuple(
            (root / "Docs" / name, root / "Docs" / directory, extra)
            for name, directory, extra in (
                ("SCHOLIUM_SPEC.md", "Specification", (root / "Design.md",)),
                ("IMPLEMENTATION_ARCHITECTURE.md", "Architecture", ()),
                ("IMPLEMENTATION_STATUS.md", "Status", ()),
            )
        )
        diagnostics = io.StringIO()
        with patch.object(validator, "REPOSITORY_ROOT", root), \
                patch.object(validator, "MANIFESTS", manifests), \
                redirect_stderr(diagnostics), self.assertRaises(SystemExit):
            validator.main()
        self.assertIn("repeated maintained paragraph", diagnostics.getvalue())
        self.assertIn("nested/Extra.md", diagnostics.getvalue())


if __name__ == "__main__":
    unittest.main()
