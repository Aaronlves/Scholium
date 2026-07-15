#!/usr/bin/env python3
"""Validate Scholium performance JSONL and produce a privacy-safe report."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
from pathlib import Path


METRICS = (
    "warm_library_launch",
    "indexed_search",
    "warm_read_activation",
    "cold_read_activation",
)
THRESHOLDS_MS = {
    "warm_library_launch": 1_000.0,
    "indexed_search": 100.0,
    "warm_read_activation": 300.0,
    "cold_read_activation": 1_000.0,
}
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
}


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
    return parser.parse_args()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def nearest_rank(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    index = max(0, math.ceil(percentile * len(ordered)) - 1)
    return ordered[index]


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


def main() -> None:
    arguments = parse_args()
    if arguments.warmups < 0 or arguments.samples <= 0:
        raise SystemExit("Warm-ups must be nonnegative and samples must be positive.")
    if arguments.evidence_class == "product_gate" and (
        arguments.warmups != 5 or arguments.samples != 30
    ):
        raise SystemExit("A product gate requires exactly 5 warm-ups and 30 retained samples.")
    if not arguments.environment.is_file():
        raise SystemExit("Missing environment metadata.")

    summaries: dict[str, object] = {}
    raw_durations: dict[str, object] = {}
    all_pass = True
    for metric in METRICS:
        records, measured = load_metric(
            arguments.input_dir / f"{metric}.jsonl",
            metric,
            arguments.run_id,
            arguments.warmups,
            arguments.samples,
        )
        p95 = nearest_rank(measured, 0.95)
        passed = p95 < THRESHOLDS_MS[metric]
        all_pass = all_pass and passed
        summaries[metric] = {
            "sample_count": len(measured),
            "warmup_count": arguments.warmups,
            "p50_ms": nearest_rank(measured, 0.50),
            "p95_ms": p95,
            "maximum_ms": max(measured),
            "mean_ms": statistics.fmean(measured),
            "threshold_ms_exclusive": THRESHOLDS_MS[metric],
            "threshold_met": passed,
            "correctness_passed": True,
        }
        raw_durations[metric] = {
            "warmups_ms": [float(record["duration_ms"]) for record in records[: arguments.warmups]],
            "retained_ms": measured,
        }

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
    main()
