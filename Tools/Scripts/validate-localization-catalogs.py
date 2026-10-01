#!/usr/bin/env python3
"""Check complete translations and formatting arguments without erasing types."""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import sys


FORMAT = re.compile(
    r"%(?:(\d+)\$)?[-+#0 ']*"
    r"(?:\d+|\*(?:(\d+)\$)?)?"
    r"(?:\.(?:\d+|\*(?:(\d+)\$)?))?"
    r"(hh|ll|h|l|q|L|z|t|j)?([@diouxXfFeEgGaAcCsSp%])"
)
TEMPLATE = re.compile(r"\{([A-Za-z][A-Za-z0-9_]*)\}")
ASCII_PUNCTUATION = re.compile(r"\.\.\.|[,;!?()]|: ")


def arguments(value):
    """Compare positions and ABI types; allow explicit translation reordering."""
    result = Counter()
    next_position = 1
    cursor = 0
    while (cursor := value.find("%", cursor)) >= 0:
        match = FORMAT.match(value, cursor)
        if not match:
            following = value[cursor + 1:cursor + 2]
            if following and (following.isascii() and following.isalnum()
                              or following in "@$*.+-#"):
                raise ValueError(f"Invalid format placeholder at position {cursor}: {value!r}")
            cursor += 1
            continue
        cursor = match.end()
        position, width_position, precision_position, length, conversion = match.groups()
        if any(item == "0" for item in [position, width_position, precision_position]):
            raise ValueError("Format argument positions start at 1")
        if conversion == "%":
            continue
        token = match.group()
        # Star width and precision consume C int arguments before the value.
        for explicit in [width_position] if "*" in token.split(".")[0] else []:
            result[(int(explicit) if explicit else next_position, "int")] += 1
            if not explicit:
                next_position += 1
        if ".*" in token:
            result[(int(precision_position) if precision_position else next_position, "int")] += 1
            if not precision_position:
                next_position += 1
        index = int(position) if position else next_position
        if not position:
            next_position += 1
        if conversion == "@":
            kind = "object"
        elif conversion in "diouxX":
            kind = (length or "") + ("signed" if conversion in "di" else "unsigned")
        elif conversion in "fFeEgGaA":
            kind = "long-double" if length == "L" else "double"
        else:
            kind = (length or "") + conversion
        result[(index, kind)] += 1
    return result, Counter(TEMPLATE.findall(value))


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key!r}")
        result[key] = value
    return result


def units(node):
    if not isinstance(node, dict):
        return
    if "stringUnit" in node:
        yield node["stringUnit"]
    for name, value in node.items():
        if name != "stringUnit" and isinstance(value, dict):
            yield from units(value)


def validate(catalog, name):
    errors = []
    if catalog.get("sourceLanguage") != "en":
        errors.append(f"{name}: source language must be en")
    for key, entry in catalog.get("strings", {}).items():
        localizations = entry.get("localizations", {})
        english = localizations.get("en", {}).get("stringUnit", {}).get("value", key)
        chinese = list(units(localizations.get("zh-Hans", {})))
        if not chinese:
            errors.append(f"{name}: {key!r}: missing zh-Hans translation")
        for unit in chinese:
            value = unit.get("value")
            if unit.get("state") != "translated" or not isinstance(value, str):
                errors.append(f"{name}: {key!r}: zh-Hans is not translated")
                continue
            if key and not value.strip():
                errors.append(f"{name}: {key!r}: empty zh-Hans translation")
            try:
                key_arguments = arguments(key)
                if key_arguments != (Counter(), Counter()) and key_arguments != arguments(english):
                    errors.append(f"{name}: {key!r}: English changed the source formatting arguments")
                if arguments(english) != arguments(value):
                    errors.append(f"{name}: {key!r}: formatting argument positions or types changed")
            except ValueError as error:
                errors.append(f"{name}: {key!r}: {error}")
            if ASCII_PUNCTUATION.search(value):
                errors.append(f"{name}: {key!r}: ASCII punctuation in zh-Hans interface prose")
    return errors


def self_test():
    assert arguments("%@ has %lld items") == arguments("%2$lld 项属于 %1$@")
    assert arguments("%@ %lld") != arguments("%@ %ld")
    assert arguments("%@ %@") != arguments("%1$@ %1$@")
    assert arguments("%lld") != arguments("%llu")
    assert arguments("%% %@") == arguments("%@ %%")
    assert arguments("%*.*f") == arguments("%3$*1$.*2$f")
    assert arguments("Show {title}") == arguments("显示“{title}”")
    assert arguments("{title} {title}") != arguments("{title}")
    for invalid in ["%@ %n", "%@ %Q", "%@ %1$", "%0$@"]:
        try:
            arguments(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError(f"Invalid format was accepted: {invalid}")
    assert arguments("100%") == arguments("50% 完成")
    valid = {"sourceLanguage": "en", "strings": {"%@ %lld": {"localizations": {
        "zh-Hans": {"stringUnit": {"state": "translated", "value": "%2$lld 项属于 %1$@"}}
    }}}}
    assert not validate(valid, "test")
    unit = valid["strings"]["%@ %lld"]["localizations"]["zh-Hans"]["stringUnit"]
    for value in ["", "%@ %ld", "%@ %lld,", "%@"]:
        unit["value"] = value
        assert validate(valid, "test")
    unit.update(state="needs_review", value="%@ %lld")
    assert validate(valid, "test")
    valid["strings"]["%@ %lld"]["localizations"] = {
        language: {"stringUnit": {"state": "translated", "value": "%lld %lld"}}
        for language in ["en", "zh-Hans"]
    }
    assert validate(valid, "test")
    try:
        json.loads('{"strings": {}, "strings": {}}', object_pairs_hook=unique_object)
    except ValueError:
        pass
    else:
        raise AssertionError("Duplicate catalog keys were accepted")
    print("Localization catalog validator self-test passed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("catalogs", nargs="*", type=Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--stringsdata-root", type=Path)
    args = parser.parse_args()
    if args.self_test:
        self_test()
    errors = []
    count = 0
    tables = {}
    for path in args.catalogs:
        try:
            catalog = json.loads(path.read_text(), object_pairs_hook=unique_object)
            errors.extend(validate(catalog, path.name))
            count += len(catalog.get("strings", {}))
            tables[path.stem] = catalog.get("strings", {})
        except (ValueError, OSError) as error:
            errors.append(f"{path.name}: {error}")
    if args.stringsdata_root:
        sources = [path for path in args.stringsdata_root.rglob("*.stringsdata")
                   if any(part == "ScholiumApp.build" or
                          (part.startswith("ScholiumApp-") and part.endswith(".build"))
                          for part in path.parts)]
        if not sources:
            errors.append("Compiler emitted no ScholiumApp localization source data")
        for source in sources:
            data = json.loads(source.read_text(), object_pairs_hook=unique_object)
            for table, entries in data.get("tables", {}).items():
                for entry in entries:
                    if entry["key"] not in tables.get(table, {}):
                        errors.append(f"{source.name}: {table}: missing compiler key {entry['key']!r}")
                        continue
                    localizations = tables[table][entry["key"]].get("localizations", {})
                    try:
                        source_arguments = arguments(entry.get("value", entry["key"]))
                        for language in ["en", "zh-Hans"]:
                            for unit in units(localizations.get(language, {})):
                                if arguments(unit.get("value", "")) != source_arguments:
                                    errors.append(f"{source.name}: {entry['key']!r}: {language} changed compiler arguments")
                    except ValueError as error:
                        errors.append(f"{source.name}: {entry['key']!r}: {error}")
    if errors:
        for error in errors[:30]:
            print(error, file=sys.stderr)
        print(f"Localization catalog validation failed: {len(errors)} issue(s).", file=sys.stderr)
        return 1
    if args.catalogs:
        print(f"Localization catalogs validated: {count} entries, argument types and positions preserved.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
