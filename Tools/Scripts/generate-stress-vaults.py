#!/usr/bin/env python3
"""Create a deterministic, nonprivate Triptych for stress diagnostics.

The unchanged standard 500-Note fixture is the baseline. Register 01-analyses,
02-topics and 03-works separately, never their parent. Generated data is not a
performance result or release gate. Use disposable copies for mutating tests.
"""

import argparse
import contextlib
import hashlib
import io
import json
import posixpath
import re
import runpy
import struct
import zlib
from pathlib import Path

ROLES = ("01-analyses", "02-topics", "03-works")
# ScholiumContracts/VaultSourceReadLimits.swift; checked by the generator test.
MAXIMUM_NOTE_BYTES = 8 * 1024 * 1024
IMAGE_SIZE = (320, 224)
LARGE_IMAGE_SIZE = (1600, 1200)
LARGE_IMAGE_COUNT = 4
SCENARIO_PATHS = {
    "entry": "02-topics/Stress/Stress Start.md",
    "long_prose": "01-analyses/Stress/Stress Long Prose.md",
    "near_source_limit": "01-analyses/Stress/Stress Near Source Limit.md",
    "dense_links": "02-topics/Stress/Stress Dense Links.md",
    "nested_callouts": "02-topics/Stress/Stress Nested Callouts.md",
    "image_gallery": "02-topics/Stress/Stress Image Gallery.md",
    "format_matrix": "03-works/Stress/Stress Format Matrix.md",
    "source_fidelity": "03-works/Stress/Stress Source Fidelity.md",
}


def note_source(title, body, number=0):
    return (
        "---\nsummary: Synthetic nonprivate stress fixture; no scholarly claims.\n"
        f"keywords: [stress-fixture, 压力测试, stress-{number:06d}]\n"
        f"stress_sequence: {number}\nfixture_only: true\n---\n\n# {title}\n\n"
        "全部内容为合成测试材料，不是引文、文献分析或研究结论。\n\n" + body
    )


def sized_prose(title, target_bytes, number):
    prefix = note_source(title, "", number)
    paragraphs = [prefix]
    size = len(prefix.encode("utf-8"))
    paragraph = 0
    while size < target_bytes:
        text = (
            f"## Section {paragraph:05d} · 段落 {number:06d}-{paragraph:05d}\n\n"
            f"Record {number:06d}, paragraph {paragraph:05d}, marker stress-token-{number:06d}. "
            "This synthetic paragraph tests wrapping, navigation, indexing and revision handling. "
            "Its identifiers distinguish otherwise similar passages during search. "
            "中文与 English 混排，组合字符 café é、希腊字母 αβγ 以及标点用于检查源位置。 "
            "The fixture makes no claim about any philosopher, publication or historical event.\n\n"
        )
        paragraphs.append(text)
        size += len(text.encode("utf-8"))
        paragraph += 1
    # Keep every complete UTF-8 paragraph; pad the final byte distance safely.
    if size > target_bytes:
        size -= len(paragraphs.pop().encode("utf-8"))
    paragraphs.append("x" * (target_bytes - size))
    return "".join(paragraphs).encode("utf-8")


def png(number, size=IMAGE_SIZE):
    """Distinct, deterministic RGB images without network or image libraries."""
    width, height = size
    pixels = bytearray()
    for y in range(height):
        pixels.append(0)
        for x in range(width):
            pixels.extend(((x + number * 17) % 256,
                           (y * 2 + number * 29) % 256,
                           ((x // (8 + number // 256) + y // 8) * 11 + number * 43) % 256))

    def chunk(kind, data):
        return struct.pack("!I", len(data)) + kind + data + struct.pack("!I", zlib.crc32(kind + data))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack("!2I5B", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(pixels, 6)) + chunk(b"IEND", b""))


def corpus_path(index):
    role = ROLES[(index - 1) % len(ROLES)]
    if index % 37 == 0:
        folder = "Stress Corpus/Deep/一/Two/三/Four/五/Six/七/Eight"
        # Deep duplicate names repeat in the same role every 37 × 53 × 3 Notes.
        # Keep their first locations stable; later cycles need distinct parents.
        duplicate_cycle = (index - 1) // (37 * 53 * len(ROLES))
        if index % 53 == 0 and duplicate_cycle:
            folder += f"/Duplicate-Cycle-{duplicate_cycle:04d}"
    else:
        folder = f"Stress Corpus/Batch-{(index - 1) // 32:04d}"
    filename = "Stress Duplicate" if index % 53 == 0 else f"Stress Note {index:06d}"
    return f"{role}/{folder}/{filename}.md"


def search_oracles(notes):
    """Independent expected Note counts from authored fixture construction.

    These queries use the lexical/property grammar owned by specification 04.
    No application parser, tokenizer, index or search result computes the oracle.
    """
    extra_count = notes - 500
    scenario_count = min(extra_count, len(SCENARIO_PATHS))
    ordinary_count = extra_count - scenario_count
    oracles = []
    if ordinary_count:
        oracles.append({"label": "rare_body", "query": 'body:"stress-token-000001"',
                        "expected_count": 1, "expected_paths": [corpus_path(1)]})
    if scenario_count > list(SCENARIO_PATHS).index("long_prose"):
        oracles.append({"label": "rare_title", "query": 'title:"Stress Long Prose"',
                        "expected_count": 1, "expected_paths": [SCENARIO_PATHS["long_prose"]]})
    oracles.extend((
        {"label": "broad_keyword", "query": 'keyword:"stress-fixture"', "expected_count": extra_count},
        {"label": "broad_property", "query": "property:fixture_only=true", "expected_count": extra_count},
        {"label": "broad_cjk_body", "query": 'body:"全部内容为合成测试材料"', "expected_count": extra_count},
        {"label": "no_result", "query": 'body:"scholium-stress-no-result-9f4e7dca"',
         "expected_count": 0, "expected_paths": []},
    ))
    return oracles


def image_link(path, number, large=False):
    filename = f"image-large-{number:04d}.png" if large else f"image-{number:04d}.png"
    image = f"02-topics/Attachments/stress/{filename}"
    relative = posixpath.relpath(image, posixpath.dirname(path))
    return f"![Synthetic image {number:04d}]({relative})\n\n"


def format_blocks(number):
    return (
        f"### Format block {number:04d}\n\n"
        "**bold** *emphasis* ~~deleted~~ ==highlight== `inline [[literal]]` "
        "\\*escaped\\* 中文 café é 🧭 αβγ & < >.\n\n"
        f"[[QA Topic|Resolved {number}]]{{{{Synthetic annotation {number}.}}}} "
        f"[[Stress Missing Matrix {number}]] [[同名笔记]]\n\n"
        f"> [!state] Mixed Callout {number}\n"
        "> **formatted** [[QA Topic]] and $x^2$.\n>\n"
        "> > [!flag] Nested\n> > `literal` and [[QA Work]].\n\n"
        "| Synthetic key | 中文 | Value |\n| :--- | :---: | ---: |\n"
        f"| stress-{number:04d} | 合成内容 | {number * 17} |\n"
        "| escaped \\| pipe | **bold** | `code` |\n\n"
        f"Footnote marker[^stress-{number:04d}] and inline math $a_{{{number}}}^2 + b^2 = c^2$.\n\n"
        "$$\n\\int_0^1 x^2\\,dx = \\frac{1}{3}\n$$\n\n"
        "```mermaid\nflowchart LR\n  Read --> Edit\n  Edit --> Save\n```\n\n"
        "```text\n[[not-a-rendered-connection]]\n> [!NOTE] not a rendered Callout\n```\n\n"
        "- [ ] Synthetic pending item\n- [x] Synthetic completed item\n\n"
        f"[^stress-{number:04d}]: Synthetic footnote {number}; no source attribution.\n\n"
    )


def generate(root, notes=5000, images=240):
    if root.exists() or root.is_symlink():
        raise ValueError(f"Destination already exists; refusing to replace it: {root}")
    if not 500 <= notes <= 20000:
        raise ValueError("--notes must be between 500 and 20000")
    if not 1 <= images <= 512:
        raise ValueError("--images must be between 1 and 512")

    # Reuse the canonical generator rather than drift from its QA entrypoints.
    standard = runpy.run_path(str(Path(__file__).with_name("generate-test-vaults.py")))
    with contextlib.redirect_stdout(io.StringIO()):
        standard["generate"](root)

    def put(path, content):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open("xb") as output:
            output.write(content.encode("utf-8") if isinstance(content, str) else content)

    extra_count = notes - 500
    scenario_count = min(extra_count, len(SCENARIO_PATHS))
    ordinary_count = extra_count - scenario_count
    scenario_paths = dict(list(SCENARIO_PATHS.items())[:scenario_count])
    if scenario_count:
        for image in range(images):
            put(f"02-topics/Attachments/stress/image-{image:04d}.png", png(image))
        for image in range(LARGE_IMAGE_COUNT):
            put(f"02-topics/Attachments/stress/image-large-{image:04d}.png",
                png(1000 + image, LARGE_IMAGE_SIZE))

    for index in range(1, ordinary_count + 1):
        path = corpus_path(index)
        title = Path(path).stem
        content = sized_prose(title, 512 * 1024 if index % 192 == 0 else 4096 + (index % 8) * 1024, index)
        links = (
            "\n\n[[QA Topic]]{{Synthetic cross-library navigation; not evidence.}}\n\n"
            "[[Stress Start]]\n\n[[同名笔记]]\n\n"
            f"[[Stress Missing {index:06d}]]\n\n"
        )
        if index > 1:
            previous = Path(corpus_path(index - 1)).stem
            links += f"[[{previous}|Previous synthetic note]]\n\n"
        content += links.encode("utf-8")
        if index % 11 == 0:
            content += format_blocks(index).encode("utf-8")
        if index % 7 == 0:
            content += image_link(path, index % images).encode("utf-8")
        if index % 13 == 0:
            content = b"\xef\xbb\xbf" + content.replace(b"\n", b"\r\n")
        if index % 17 == 0:
            content = content.rstrip(b"\n\r")
        put(path, content)

    for scenario, path in scenario_paths.items():
        title = Path(path).stem
        if scenario in ("long_prose", "near_source_limit"):
            target = 512 * 1024 if scenario == "long_prose" else MAXIMUM_NOTE_BYTES - 1024
            put(path, sized_prose(title, target, 800000 + list(SCENARIO_PATHS).index(scenario)))
            continue
        if scenario == "entry":
            body = "## Scenarios\n\n" + "".join(
                f"- [[{Path(target).stem}]] · {name}\n" for name, target in scenario_paths.items() if name != "entry")
            body += ("\n## Usage\n\nOnly synthetic data. Use disposable copies for edits, conflicts, moves and reloads. "
                     "Measure cold and warm opening separately; this fixture makes no performance claims. "
                     "Register the three numbered vault folders separately, never the parent.\n\n")
        elif scenario == "dense_links":
            targets = [Path(corpus_path(index)).stem for index in range(1, ordinary_count + 1)] or ["QA Topic"]
            body = "## Resolved, unresolved and ambiguous targets\n\n"
            for index in range(2400):
                target = targets[index % len(targets)]
                body += (f"### Link batch {index:04d}\n\n"
                         f"[[{target}]]{{{{Synthetic navigation annotation {index:04d}.}}}} "
                         f"[[Stress Missing Dense {index:04d}]] [[同名笔记]] [[QA Topic|Baseline target]]\n\n")
        elif scenario == "nested_callouts":
            kinds = ("orient", "cite", "connect", "state", "illustrate", "quote", "flag", "NOTE")
            parts = []
            for index in range(640):
                depth = 1 + index % 4
                lines = [f"## Callout group {index:04d}\n\n"]
                for level in range(1, depth + 1):
                    prefix = "> " * level
                    lines.extend((f"{prefix}[!{kinds[(index + level) % len(kinds)]}] Synthetic {index}-{level}\n",
                                  f"{prefix}Mixed 中文 English **content**, `code`, and [[QA Topic]].\n",
                                  f"{prefix}\n"))
                parts.append("".join(lines) + "\n")
            body = "".join(parts)
        elif scenario == "image_gallery":
            body = "## Distinct local images\n\n" + "".join(
                f"### Image {image:04d}\n\n" + image_link(path, image) for image in range(images))
            body += "## Larger local images\n\n" + "".join(
                f"### Large image {image:04d}\n\n" + image_link(path, image, large=True)
                for image in range(LARGE_IMAGE_COUNT))
        elif scenario == "format_matrix":
            body = "".join(format_blocks(index) for index in range(1, 121))
        else:
            source = note_source(title, "<!-- Source bytes must remain authoritative. -->\n\n"
                                 "中文 English café é 🧭; no final newline.", 900000)
            put(path, b"\xef\xbb\xbf" + source.replace("\n", "\r\n").encode("utf-8"))
            continue
        put(path, note_source(title, body, 800000 + list(SCENARIO_PATHS).index(scenario)))

    inventory = {}
    totals = {"notes": 0, "note_bytes": 0, "files": 0, "bytes": 0, "png_images": 0,
              "wikilink_occurrences": 0, "callout_markers": 0, "markdown_image_references": 0,
              "mermaid_blocks": 0, "bom_notes": 0, "crlf_notes": 0, "maximum_note_bytes": 0}
    role_counts = {role: 0 for role in ROLES}
    for target in sorted(root.rglob("*")):
        if not target.is_file():
            continue
        path = target.relative_to(root).as_posix()
        data = target.read_bytes()
        inventory[path] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
        totals["files"] += 1
        totals["bytes"] += len(data)
        if target.suffix.lower() == ".png":
            totals["png_images"] += 1
        if path.split("/")[0] in ROLES and target.suffix == ".md":
            role_counts[path.split("/")[0]] += 1
            totals["notes"] += 1
            totals["note_bytes"] += len(data)
            totals["maximum_note_bytes"] = max(totals["maximum_note_bytes"], len(data))
            totals["bom_notes"] += int(data.startswith(b"\xef\xbb\xbf"))
            totals["crlf_notes"] += int(b"\r\n" in data)
            totals["wikilink_occurrences"] += len(re.findall(rb"\[\[[^\]\r\n]+\]\]", data))
            totals["callout_markers"] += len(re.findall(rb"(?m)^\s*(?:>\s*)+\[![A-Za-z]+\]", data))
            totals["markdown_image_references"] += len(re.findall(rb"!\[[^\]\r\n]*\]\([^\)\r\n]+\)", data))
            totals["mermaid_blocks"] += data.count(b"```mermaid")

    assert totals["notes"] == notes
    assert totals["maximum_note_bytes"] <= MAXIMUM_NOTE_BYTES
    manifest = {
        "schema_version": 1, "synthetic_nonprivate": True, "generator_notes": notes,
        "registration_roots": list(ROLES), "scenarios": scenario_paths,
        "search_oracles": search_oracles(notes),
        "baseline_generator": "Tools/Scripts/generate-test-vaults.py",
        "baseline_files_preserved": True, "counts": totals, "notes_by_role": role_counts,
        "syntax_counts_are_lexical_not_parser_results": True,
        "inventory_excludes": ["stress-manifest.json"],
        "stress_image_dimensions": list(IMAGE_SIZE),
        "stress_large_image_dimensions": list(LARGE_IMAGE_SIZE),
        "stress_large_image_count": LARGE_IMAGE_COUNT if scenario_count else 0,
        "stress_gallery_decoded_rgb_bytes": (images * IMAGE_SIZE[0] * IMAGE_SIZE[1] * 3
                                           + LARGE_IMAGE_COUNT * LARGE_IMAGE_SIZE[0] * LARGE_IMAGE_SIZE[1] * 3)
                                          if scenario_count else 0,
        "stress_gallery_decoded_rgba_bytes": (images * IMAGE_SIZE[0] * IMAGE_SIZE[1] * 4
                                            + LARGE_IMAGE_COUNT * LARGE_IMAGE_SIZE[0] * LARGE_IMAGE_SIZE[1] * 4)
                                           if scenario_count else 0,
        "files": inventory,
    }
    put("stress-manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"Created {root}: {totals['notes']} Notes, {totals['note_bytes']:,} source bytes, "
          f"{totals['png_images']} PNGs; no preconfigured portable state.")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("destination", type=Path, help="New, nonexistent directory; use a path under .build/")
    parser.add_argument("--notes", type=int, default=5000,
                        help="Total vault Notes, 500–20000 (default: 5000); >=508 includes all 8 scenarios")
    parser.add_argument("--images", type=int, default=240,
                        help="Distinct 320×224 PNGs, 1–512 (default: 240), plus four 1600×1200 PNGs")
    args = parser.parse_args()
    try:
        # Do not resolve a final symlink: even dangling destinations must be refused.
        generate(args.destination.absolute(), args.notes, args.images)
    except (ValueError, FileExistsError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
