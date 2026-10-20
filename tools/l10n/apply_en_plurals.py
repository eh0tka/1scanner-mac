#!/usr/bin/env python3
"""Writes the English singular forms from en_plurals.json into the string catalog as plural variations.

Run from the app folder after `xcodebuild -exportLocalizations` has refreshed the catalog from the code:
    python3 tools/l10n/apply_en_plurals.py
"""
import json
import os
import sys

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
catalog_path = os.path.join(root, "OneScannerMac", "Resources", "Localizable.xcstrings")
plurals = json.load(open(os.path.join(root, "tools", "l10n", "en_plurals.json")))
catalog = json.load(open(catalog_path))


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


missing = [key for key in plurals if key not in catalog["strings"]]
if missing:
    sys.exit(f"Not in the catalog (export first, or remove from en_plurals.json): {missing}")
for key, one in plurals.items():
    entry = catalog["strings"][key]
    entry.setdefault("localizations", {})["en"] = {"variations": {"plural": {"one": unit(one), "other": unit(key)}}}
with open(catalog_path, "w") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, separators=(",", " : "))
    f.write("\n")
print(f"English plurals: {len(plurals)}")
