#!/usr/bin/env python3
"""Reject catalog drift even when a changed MCP surface keeps the same count."""

from pathlib import Path
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[2]
GUARD = runpy.run_path(str(ROOT / "Tools/Scripts/verify-agent-helper.py"))
SOURCE = (ROOT / "ScholiumContracts/ScholiumMCPContracts.swift").read_text(encoding="utf-8")


class MCPSurfaceTests(unittest.TestCase):
    def check_source(self, source):
        GUARD["check_source_surface"](source)

    def replace_source(self, before, after):
        self.assertIn(before, SOURCE)
        return SOURCE.replace(before, after, 1)

    def test_current_closed_catalog(self):
        self.check_source(SOURCE)
        self.assertEqual(len(GUARD["RESEARCH_TOOLS"]), 19)
        self.assertEqual(len(GUARD["CHAT_CONTROLS"]), 5)

    def test_count_preserving_renamed_wire_identity_is_rejected(self):
        for name in ["scholium_read_note", "scholium_observe_current_state"]:
            with self.subTest(name=name), self.assertRaisesRegex(AssertionError, "wire identities"):
                self.check_source(self.replace_source(f'"{name}"', f'"{name}_unexpected"'))

    def test_removed_duplicate_and_unexpected_cases_are_rejected(self):
        case = '    case observeCurrentState = "scholium_observe_current_state"\n'
        for replacement in ["", case + case, case + '    case extra = "scholium_extra"\n']:
            with self.subTest(replacement=replacement), self.assertRaisesRegex(AssertionError, "wire identities"):
                self.check_source(self.replace_source(case, replacement))

    def test_commented_out_case_cannot_satisfy_catalog(self):
        with self.assertRaisesRegex(AssertionError, "wire identities"):
            self.check_source(self.replace_source("    case observeCurrentState =", "    // case observeCurrentState ="))

    def test_chat_control_cannot_become_external_or_be_replaced_by_research_tool(self):
        for replacement in ["", ", .readNote", ", .configureChat"]:
            with self.subTest(replacement=replacement), self.assertRaisesRegex(AssertionError, "Chat-only classification"):
                self.check_source(self.replace_source(", .observeCurrentState: true", replacement + ": true"))

    def test_nonclosed_classification_and_unparsed_cases_fail_closed(self):
        for before, after in [
            ("default: false", "default: true"),
            ("switch self {\n        case .capabilities", "switch self {\n        case .capabilities where false"),
            ('case browse = "scholium_browse"', 'case browse = "scholium_browse", extra'),
        ]:
            with self.subTest(after=after), self.assertRaisesRegex(AssertionError, "unrecognized closed"):
                self.check_source(self.replace_source(before, after))

    def test_mutation_delivery_cannot_be_classified_as_a_definite_read_failure(self):
        for replacement in [".readNote", ".configureSkill", ""]:
            with self.subTest(replacement=replacement), self.assertRaisesRegex(AssertionError, "persistent mutation classification"):
                self.check_source(self.replace_source(
                    "case .createNote, .updateNote,", f"case {replacement}, .updateNote," if replacement else "case .updateNote,"))

    def test_unrecognized_mutation_classification_fails_closed(self):
        with self.assertRaisesRegex(AssertionError, "unrecognized closed"):
            self.check_source(self.replace_source("public var mayMutatePersistentState: Bool", "public var mayMutatePersistentState: Int"))

    def test_missing_or_duplicate_enum_fails_closed(self):
        for source in ["", SOURCE + SOURCE]:
            with self.subTest(length=len(source)), self.assertRaisesRegex(AssertionError, "one closed tool enum"):
                self.check_source(source)

    def test_runtime_catalog_rejects_duplicates_missing_names_and_scope_swaps(self):
        research = list(GUARD["RESEARCH_TOOLS"].values())
        chat = list(GUARD["CHAT_CONTROLS"].values())
        scoped = research + chat
        for actual, expected in [
            (research + [chat[-1]], research),
            (research[:-1] + [chat[-1]], research),
            (research[:-1] + [research[0]], research),
            (scoped[:-1], scoped),
            (scoped[:-1] + ["scholium_unexpected"], scoped),
            (scoped + [chat[-1]], scoped),
        ]:
            with self.subTest(actual=actual), self.assertRaisesRegex(AssertionError, "MCP surface guard failed"):
                GUARD["require_catalog"](actual, expected, "fixture")

    def test_runtime_catalog_allows_reordering_without_changing_membership(self):
        for names in [list(GUARD["RESEARCH_TOOLS"].values()),
                      [*GUARD["RESEARCH_TOOLS"].values(), *GUARD["CHAT_CONTROLS"].values()]]:
            GUARD["require_catalog"](reversed(names), names, "fixture")


if __name__ == "__main__":
    unittest.main()
