#!/usr/bin/env python3
"""Validate Scholium performance JSONL and produce a privacy-safe report."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
import sys
import tempfile
from pathlib import Path


LATENCY_METRICS = (
    "warm_library_launch",
    "indexed_search",
    "warm_read_activation",
    "cold_read_activation",
    "editor_key_to_paint",
    "editor_mode_transition",
)
ALL_METRICS = LATENCY_METRICS + ("editor_retained_memory",)
THRESHOLDS_MS = {
    "warm_library_launch": 1_000.0,
    "indexed_search": 100.0,
    "warm_read_activation": 300.0,
    "cold_read_activation": 1_000.0,
    "editor_key_to_paint": 100.0,
    "editor_mode_transition": 100.0,
}
MAXIMUM_LIMITS_MS = {
    "editor_key_to_paint": 200.0,
    "editor_mode_transition": 200.0,
}
REQUIRED_EDITOR_METRICS = (
    "editor_key_to_paint",
    "editor_mode_transition",
    "editor_cached_preview",
    "warm_edit_activation",
    "cold_edit_activation",
    "editor_visible_projection",
    "editor_retained_memory",
)
EXPECTED_COUNTS = {
    "warm_library_launch": 267,
    "indexed_search": 1,
}
ALLOWED_KEYS = {
    "schema",
    "metric",
    "run_id",
    "sample",
    "duration_ms",
    "completed_uptime_ns",
    "observed_count",
    "observed_mode",
    "acknowledged_duration_ms",
    "bridge_started_duration_ms",
    "bridge_roundtrip_duration_ms",
    "layout_duration_ms",
}
MEMORY_ROLES = ("app", "gpu", "networking", "web_content")
MEMORY_ALLOWED_KEYS = {
    "schema",
    "sample",
    "transition",
    "mode",
    "sample_uptime_ns",
    "scope",
    "process_count",
    "resident_bytes",
    "role_process_counts",
    "role_resident_bytes",
}
MEMORY_TRANSITIONS = 50
MEMORY_TAIL_GROWTH_LIMIT = 0.05


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--environment", required=True, type=Path)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--warmups", required=True, type=int)
    parser.add_argument("--samples", required=True, type=int)
    parser.add_argument(
        "--evidence-class",
        required=True,
        choices=("scenario_only", "product_gate"),
    )
    parser.add_argument(
        "--metrics",
        nargs="+",
        choices=ALL_METRICS,
        default=list(ALL_METRICS),
    )
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def nearest_rank(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    index = max(0, math.ceil(percentile * len(ordered)) - 1)
    return ordered[index]


def summarize_latency(metric: str, measured: list[float]) -> dict[str, object]:
    p95 = nearest_rank(measured, 0.95)
    maximum = max(measured)
    threshold_met = p95 < THRESHOLDS_MS[metric]
    maximum_limit = MAXIMUM_LIMITS_MS.get(metric)
    maximum_limit_met = maximum_limit is None or maximum < maximum_limit
    return {
        "p50_ms": nearest_rank(measured, 0.50),
        "p95_ms": p95,
        "maximum_ms": maximum,
        "mean_ms": statistics.fmean(measured),
        "threshold_ms_exclusive": THRESHOLDS_MS[metric],
        "threshold_met": threshold_met,
        "maximum_limit_ms_exclusive": maximum_limit,
        "maximum_limit_met": maximum_limit_met,
        "passed": threshold_met and maximum_limit_met,
    }


def missing_required_editor_metrics(summaries: dict[str, object]) -> list[str]:
    return [metric for metric in REQUIRED_EDITOR_METRICS if metric not in summaries]


def load_metric(
    path: Path,
    metric: str,
    run_id: str,
    warmups: int,
    samples: int,
) -> tuple[list[dict[str, object]], list[float]]:
    if not path.is_file():
        raise SystemExit(f"Missing metric results: {path}")
    records: list[dict[str, object]] = []
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            record = json.loads(raw_line)
        except json.JSONDecodeError as error:
            raise SystemExit(f"{path}:{line_number}: invalid JSON: {error}") from error
        if not isinstance(record, dict):
            raise SystemExit(f"{path}:{line_number}: record must be an object")
        unexpected = set(record) - ALLOWED_KEYS
        if unexpected:
            raise SystemExit(
                f"{path}:{line_number}: privacy contract rejected keys {sorted(unexpected)}"
            )
        if record.get("schema") != "scholium-performance-v1":
            raise SystemExit(f"{path}:{line_number}: unsupported schema")
        if record.get("metric") != metric or record.get("run_id") != run_id:
            raise SystemExit(f"{path}:{line_number}: metric or run id mismatch")
        duration = record.get("duration_ms")
        sample = record.get("sample")
        if not isinstance(duration, (int, float)) or not math.isfinite(duration) or duration <= 0:
            raise SystemExit(f"{path}:{line_number}: invalid duration")
        if not isinstance(sample, int):
            raise SystemExit(f"{path}:{line_number}: invalid sample index")
        expected_count = EXPECTED_COUNTS.get(metric)
        if expected_count is not None and record.get("observed_count") != expected_count:
            raise SystemExit(f"{path}:{line_number}: correctness count mismatch")
        if expected_count is None and "observed_count" in record:
            raise SystemExit(f"{path}:{line_number}: unexpected observed count")
        if metric == "editor_mode_transition":
            expected_mode = "source" if sample % 2 == 0 else "live_preview"
            if record.get("observed_mode") != expected_mode:
                raise SystemExit(f"{path}:{line_number}: unexpected Editor mode sequence")
            acknowledged = record.get("acknowledged_duration_ms")
            bridge_started = record.get("bridge_started_duration_ms")
            bridge_roundtrip = record.get("bridge_roundtrip_duration_ms")
            layout = record.get("layout_duration_ms")
            if any(
                not isinstance(value, (int, float))
                or isinstance(value, bool)
                or not math.isfinite(value)
                or value < 0
                for value in (acknowledged, bridge_started, bridge_roundtrip, layout)
            ):
                raise SystemExit(f"{path}:{line_number}: invalid Editor phase duration")
            if abs(float(acknowledged) + float(layout) - float(duration)) > 0.001:
                raise SystemExit(f"{path}:{line_number}: Editor phases do not match duration")
            if abs(
                float(bridge_started) + float(bridge_roundtrip) - float(acknowledged)
            ) > 0.001:
                raise SystemExit(f"{path}:{line_number}: Editor bridge phases do not match acknowledgement")
        elif "observed_mode" in record:
            raise SystemExit(f"{path}:{line_number}: unexpected observed mode")
        elif any(
            phase in record
            for phase in (
                "acknowledged_duration_ms",
                "bridge_started_duration_ms",
                "bridge_roundtrip_duration_ms",
                "layout_duration_ms",
            )
        ):
            raise SystemExit(f"{path}:{line_number}: unexpected Editor phase duration")
        records.append(record)

    total = warmups + samples
    indexes = [record["sample"] for record in records]
    if indexes != list(range(total)):
        raise SystemExit(
            f"{path}: expected ordered sample indexes 0...{total - 1}, got {indexes}"
        )
    measured = [float(record["duration_ms"]) for record in records[warmups:]]
    if len(measured) != samples:
        raise SystemExit(f"{path}: expected {samples} retained samples")
    return records, measured


def load_editor_memory(path: Path) -> tuple[list[dict[str, object]], dict[str, object]]:
    if not path.is_file():
        raise SystemExit(f"Missing Editor memory results: {path}")
    records: list[dict[str, object]] = []
    expected_count = MEMORY_TRANSITIONS + 1
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            record = json.loads(raw_line)
        except json.JSONDecodeError as error:
            raise SystemExit(f"{path}:{line_number}: invalid JSON: {error}") from error
        if not isinstance(record, dict):
            raise SystemExit(f"{path}:{line_number}: record must be an object")
        unexpected = set(record) - MEMORY_ALLOWED_KEYS
        if unexpected:
            raise SystemExit(
                f"{path}:{line_number}: privacy contract rejected keys {sorted(unexpected)}"
            )
        if record.get("schema") != "scholium-process-memory-v1":
            raise SystemExit(f"{path}:{line_number}: unsupported memory schema")
        if record.get("scope") != "app_plus_attributed_webkit_services":
            raise SystemExit(f"{path}:{line_number}: unsupported process-memory scope")
        sample = record.get("sample")
        transition = record.get("transition")
        if not isinstance(sample, int) or isinstance(sample, bool) or transition != sample:
            raise SystemExit(f"{path}:{line_number}: invalid memory sample index")
        expected_mode = "live_preview" if sample % 2 == 0 else "source"
        if record.get("mode") != expected_mode:
            raise SystemExit(f"{path}:{line_number}: unexpected Editor mode sequence")
        counts = record.get("role_process_counts")
        resident = record.get("role_resident_bytes")
        if not isinstance(counts, dict) or set(counts) != set(MEMORY_ROLES):
            raise SystemExit(f"{path}:{line_number}: invalid process-role counts")
        if not isinstance(resident, dict) or set(resident) != set(MEMORY_ROLES):
            raise SystemExit(f"{path}:{line_number}: invalid process-role memory")
        if any(
            not isinstance(counts[role], int)
            or isinstance(counts[role], bool)
            or counts[role] <= 0
            for role in MEMORY_ROLES
        ):
            raise SystemExit(f"{path}:{line_number}: nonpositive process-role count")
        if any(
            not isinstance(resident[role], int)
            or isinstance(resident[role], bool)
            or resident[role] <= 0
            for role in MEMORY_ROLES
        ):
            raise SystemExit(f"{path}:{line_number}: nonpositive process-role RSS")
        if record.get("process_count") != sum(counts.values()):
            raise SystemExit(f"{path}:{line_number}: process count does not match roles")
        if record.get("resident_bytes") != sum(resident.values()):
            raise SystemExit(f"{path}:{line_number}: RSS total does not match roles")
        records.append(record)

    indexes = [record["sample"] for record in records]
    if indexes != list(range(expected_count)):
        raise SystemExit(
            f"{path}: expected ordered memory samples 0...{MEMORY_TRANSITIONS}, got {indexes}"
        )
    first_counts = records[0]["role_process_counts"]
    stable_counts = all(record["role_process_counts"] == first_counts for record in records)
    totals = [int(record["resident_bytes"]) for record in records]
    preceding_tail = totals[-20:-10]
    final_tail = totals[-10:]
    preceding_median = statistics.median(preceding_tail)
    final_median = statistics.median(final_tail)
    tail_growth_ratio = (final_median - preceding_median) / preceding_median
    monotonic_tail_growth = all(
        later >= earlier for earlier, later in zip(final_tail, final_tail[1:])
    ) and any(later > earlier for earlier, later in zip(final_tail, final_tail[1:]))
    converged = (
        stable_counts
        and not monotonic_tail_growth
        and tail_growth_ratio <= MEMORY_TAIL_GROWTH_LIMIT
    )
    summary = {
        "sample_count": len(records),
        "transition_count": MEMORY_TRANSITIONS,
        "stable_process_counts": stable_counts,
        "role_process_counts": first_counts,
        "initial_resident_bytes": totals[0],
        "maximum_resident_bytes": max(totals),
        "final_resident_bytes": totals[-1],
        "preceding_tail_median_bytes": preceding_median,
        "final_tail_median_bytes": final_median,
        "tail_growth_ratio": tail_growth_ratio,
        "tail_growth_limit_inclusive": MEMORY_TAIL_GROWTH_LIMIT,
        "monotonic_tail_growth": monotonic_tail_growth,
        "convergence_observed": converged,
        "correctness_passed": True,
    }
    return records, summary


def self_test() -> None:
    smooth = [10.0] * 29 + [199.0]
    smooth_summary = summarize_latency("editor_mode_transition", smooth)
    assert smooth_summary["threshold_met"] is True
    assert smooth_summary["maximum_limit_met"] is True
    assert smooth_summary["passed"] is True

    hard_max_failure = summarize_latency(
        "editor_mode_transition",
        [10.0] * 29 + [200.0],
    )
    assert hard_max_failure["threshold_met"] is True
    assert hard_max_failure["maximum_limit_met"] is False
    assert hard_max_failure["passed"] is False

    p95_failure = summarize_latency(
        "editor_mode_transition",
        [10.0] * 28 + [100.0, 199.0],
    )
    assert p95_failure["threshold_met"] is False
    assert p95_failure["passed"] is False

    available = {
        "editor_key_to_paint": {},
        "editor_mode_transition": {},
        "editor_retained_memory": {},
    }
    assert missing_required_editor_metrics(available) == [
        "editor_cached_preview",
        "warm_edit_activation",
        "cold_edit_activation",
        "editor_visible_projection",
    ]

    with tempfile.TemporaryDirectory(prefix="scholium-performance-self-test-") as directory:
        path = Path(directory) / "editor_mode_transition.jsonl"
        base = {
            "schema": "scholium-performance-v1",
            "metric": "editor_mode_transition",
            "run_id": "self_test",
            "duration_ms": 10.0,
            "completed_uptime_ns": 1,
        }
        records = [
            {
                **base,
                "sample": 0,
                "observed_mode": "source",
                "acknowledged_duration_ms": 7.0,
                "bridge_started_duration_ms": 2.0,
                "bridge_roundtrip_duration_ms": 5.0,
                "layout_duration_ms": 3.0,
            },
            {
                **base,
                "sample": 1,
                "observed_mode": "live_preview",
                "acknowledged_duration_ms": 8.0,
                "bridge_started_duration_ms": 3.0,
                "bridge_roundtrip_duration_ms": 5.0,
                "layout_duration_ms": 2.0,
            },
        ]
        path.write_text(
            "".join(json.dumps(record) + "\n" for record in records),
            encoding="utf-8",
        )
        loaded, measured = load_metric(path, "editor_mode_transition", "self_test", 0, 2)
        assert len(loaded) == 2 and measured == [10.0, 10.0]

        path.write_text(
            json.dumps({**records[0], "document": "Private.md"}) + "\n",
            encoding="utf-8",
        )
        try:
            load_metric(path, "editor_mode_transition", "self_test", 0, 1)
        except SystemExit as error:
            assert "privacy contract rejected keys" in str(error)
        else:
            raise AssertionError("The privacy allowlist accepted a document path.")

        path.write_text(json.dumps(records[0]) + "\n", encoding="utf-8")
        try:
            load_metric(path, "editor_mode_transition", "self_test", 0, 2)
        except SystemExit as error:
            assert "ordered sample indexes" in str(error)
        else:
            raise AssertionError("A missing Editor latency sample was accepted.")

    print("Performance summary self-test: thresholds, privacy, and completeness passed")


def main() -> None:
    arguments = parse_args()
    if arguments.warmups < 0 or arguments.samples <= 0:
        raise SystemExit("Warm-ups must be nonnegative and samples must be positive.")
    if arguments.evidence_class == "product_gate" and (
        arguments.warmups != 5 or arguments.samples != 30
    ):
        raise SystemExit("A product gate requires exactly 5 warm-ups and 30 retained samples.")
    selected_metrics = tuple(arguments.metrics)
    if len(set(selected_metrics)) != len(selected_metrics):
        raise SystemExit("Performance metrics must be unique.")
    if arguments.evidence_class == "product_gate" and set(selected_metrics) != set(ALL_METRICS):
        raise SystemExit("A product gate requires every performance metric.")
    if not arguments.environment.is_file():
        raise SystemExit("Missing environment metadata.")

    summaries: dict[str, object] = {}
    raw_durations: dict[str, object] = {}
    all_pass = True
    for metric in LATENCY_METRICS:
        if metric not in selected_metrics:
            continue
        records, measured = load_metric(
            arguments.input_dir / f"{metric}.jsonl",
            metric,
            arguments.run_id,
            arguments.warmups,
            arguments.samples,
        )
        latency = summarize_latency(metric, measured)
        passed = bool(latency.pop("passed"))
        all_pass = all_pass and passed
        summaries[metric] = {
            "sample_count": len(measured),
            "warmup_count": arguments.warmups,
            **latency,
            "correctness_passed": True,
        }
        if metric == "editor_mode_transition":
            retained_records = records[arguments.warmups :]
            for phase in (
                "acknowledged_duration_ms",
                "bridge_started_duration_ms",
                "bridge_roundtrip_duration_ms",
                "layout_duration_ms",
            ):
                values = [float(record[phase]) for record in retained_records]
                summaries[metric][phase] = {
                    "p50_ms": nearest_rank(values, 0.50),
                    "p95_ms": nearest_rank(values, 0.95),
                    "maximum_ms": max(values),
                    "mean_ms": statistics.fmean(values),
                }
        raw_durations[metric] = {
            "warmups_ms": [float(record["duration_ms"]) for record in records[: arguments.warmups]],
            "retained_ms": measured,
        }

    if "editor_retained_memory" in selected_metrics:
        memory_records, memory_summary = load_editor_memory(
            arguments.input_dir / "editor_retained_memory.jsonl"
        )
        summaries["editor_retained_memory"] = memory_summary
        raw_durations["editor_retained_memory"] = {
            "resident_bytes": [record["resident_bytes"] for record in memory_records],
            "role_resident_bytes": [record["role_resident_bytes"] for record in memory_records],
        }
        all_pass = all_pass and bool(memory_summary["convergence_observed"])
    missing_editor_metrics = missing_required_editor_metrics(summaries)
    all_pass = all_pass and not missing_editor_metrics

    gate_status = "not_applicable"
    if arguments.evidence_class == "product_gate":
        gate_status = "passed" if all_pass else "failed"
    report = {
        "schema": "scholium-performance-report-v1",
        "evidence_class": arguments.evidence_class,
        "gate_status": gate_status,
        "run_id": arguments.run_id,
        "percentile_method": "nearest-rank",
        "invalidated_trials": [],
        "measured_metrics": list(selected_metrics),
        "missing_required_editor_metrics": missing_editor_metrics,
        "environment": {
            "file": arguments.environment.name,
            "sha256": sha256(arguments.environment),
        },
        "metrics": summaries,
        "raw_durations": raw_durations,
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    if arguments.evidence_class == "product_gate" and not all_pass:
        raise SystemExit("Product performance gate failed.")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    else:
        main()
