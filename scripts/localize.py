#!/usr/bin/env python3
"""
localize.py — small helper for managing lib/localizations/*.json translation files.

Usage (normally invoked via scripts/localize.sh):

  localize.sh --check
      Validate that every locale file is valid JSON, has a language.name key,
      and has exactly the same set of leaf keys as en.json (the reference).
      Exits non-zero (and prints details) if anything doesn't match.

  localize.sh --list [--lang xx]
      Print all dot-notation leaf keys. Defaults to en.json if --lang is
      omitted. Useful for seeing the full key structure at a glance.

  localize.sh --get --lang xx --key some.nested.key
      Print the value of a single key from lib/localizations/xx.json.

  localize.sh --write --lang xx --key some.nested.key "New value"
      Set (or add) the value of a key in lib/localizations/xx.json. Creates
      intermediate objects as needed. Preserves key order/formatting via
      Python's json module (2-space indent, matching existing files).

Examples:
  ./scripts/localize.sh --check
  ./scripts/localize.sh --list --lang de
  ./scripts/localize.sh --get --lang en --key node.title
  ./scripts/localize.sh --write --lang es --key node.checkingNodeStatusTitle "Comprobando estado"
"""

import argparse
import json
import sys
from pathlib import Path

LOCALIZATIONS_DIR = Path(__file__).resolve().parent.parent / "lib" / "localizations"
REFERENCE_LOCALE = "en"


def locale_path(lang: str) -> Path:
    return LOCALIZATIONS_DIR / f"{lang}.json"


def load_locale(lang: str) -> dict:
    path = locale_path(lang)
    if not path.exists():
        print(f"error: no such locale file: {path}", file=sys.stderr)
        sys.exit(1)
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        print(f"error: {path.name} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(1)


def save_locale(lang: str, data: dict) -> None:
    path = locale_path(lang)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")


def all_locale_files():
    return sorted(LOCALIZATIONS_DIR.glob("*.json"))


def extract_leaf_keys(data, prefix=""):
    keys = set()
    for k, v in data.items():
        full_key = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            keys |= extract_leaf_keys(v, full_key)
        else:
            keys.add(full_key)
    return keys


def get_nested(data: dict, dotted_key: str):
    parts = dotted_key.split(".")
    node = data
    for part in parts:
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def set_nested(data: dict, dotted_key: str, value: str) -> None:
    parts = dotted_key.split(".")
    node = data
    for part in parts[:-1]:
        if part not in node or not isinstance(node[part], dict):
            node[part] = {}
        node = node[part]
    node[parts[-1]] = value


def cmd_check(_args) -> int:
    files = all_locale_files()
    if not files:
        print(f"error: no locale files found in {LOCALIZATIONS_DIR}", file=sys.stderr)
        return 1

    ref_path = locale_path(REFERENCE_LOCALE)
    if not ref_path.exists():
        print(f"error: reference locale '{REFERENCE_LOCALE}.json' not found", file=sys.stderr)
        return 1

    ok = True

    parsed = {}
    for path in files:
        try:
            with open(path, "r", encoding="utf-8") as f:
                parsed[path.stem] = json.load(f)
        except json.JSONDecodeError as e:
            print(f"FAIL  {path.name}: invalid JSON: {e}")
            ok = False

    for lang, data in parsed.items():
        lang_name = data.get("language", {}).get("name")
        if not isinstance(lang_name, str) or not lang_name:
            print(f"FAIL  {lang}.json: missing 'language.name' string")
            ok = False

    if REFERENCE_LOCALE not in parsed:
        print(f"error: {REFERENCE_LOCALE}.json failed to parse, cannot compare keys")
        return 1

    reference_keys = extract_leaf_keys(parsed[REFERENCE_LOCALE])

    for lang, data in parsed.items():
        if lang == REFERENCE_LOCALE:
            continue
        keys = extract_leaf_keys(data)
        missing = reference_keys - keys
        extra = keys - reference_keys
        if missing:
            print(f"FAIL  {lang}.json: missing {len(missing)} key(s):")
            for k in sorted(missing):
                print(f"        - {k}")
            ok = False
        if extra:
            print(f"FAIL  {lang}.json: has {len(extra)} extra key(s) not in {REFERENCE_LOCALE}.json:")
            for k in sorted(extra):
                print(f"        + {k}")
            ok = False

    if ok:
        print(f"OK    {len(parsed)} locale file(s) valid, all keys match {REFERENCE_LOCALE}.json")
        return 0
    return 1


def cmd_list(args) -> int:
    lang = args.lang or REFERENCE_LOCALE
    data = load_locale(lang)
    keys = sorted(extract_leaf_keys(data))
    for k in keys:
        print(k)
    return 0


def cmd_get(args) -> int:
    if not args.lang or not args.key:
        print("error: --get requires --lang and --key", file=sys.stderr)
        return 1
    data = load_locale(args.lang)
    value = get_nested(data, args.key)
    if value is None:
        print(f"error: key '{args.key}' not found in {args.lang}.json", file=sys.stderr)
        return 1
    if isinstance(value, dict):
        print(f"error: '{args.key}' is not a leaf key (it's an object) in {args.lang}.json", file=sys.stderr)
        return 1
    print(value)
    return 0


def cmd_write(args) -> int:
    if not args.lang or not args.key or args.value is None:
        print("error: --write requires --lang, --key, and a value argument", file=sys.stderr)
        return 1
    data = load_locale(args.lang)
    set_nested(data, args.key, args.value)
    save_locale(args.lang, data)
    print(f"Wrote {args.lang}.json: {args.key} = {args.value!r}")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description="Manage DeFlock localization JSON files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true", help="Validate all locale files match en.json's key structure")
    group.add_argument("--list", action="store_true", help="List all dot-notation leaf keys for a locale (default: en)")
    group.add_argument("--get", action="store_true", help="Print the value of a single key")
    group.add_argument("--write", action="store_true", help="Set the value of a single key")

    parser.add_argument("--lang", help="Language code, e.g. 'en', 'de', 'es' (filename without .json)")
    parser.add_argument("--key", help="Dot-notation key, e.g. 'node.title'")
    parser.add_argument("value", nargs="?", help="New value (only used with --write)")

    args = parser.parse_args()

    if args.check:
        sys.exit(cmd_check(args))
    elif args.list:
        sys.exit(cmd_list(args))
    elif args.get:
        sys.exit(cmd_get(args))
    elif args.write:
        sys.exit(cmd_write(args))


if __name__ == "__main__":
    main()
