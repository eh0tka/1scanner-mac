"""merge.py <app dir> <tr dir> <langs…>: writes <tr dir>/<lang>.json translations into Localizable.xcstrings.

Fails without writing anything on a missing key, a placeholder mismatch or wrong plural categories.
"""
import json, os, re, sys

app, tr, langs = sys.argv[1], sys.argv[2], sys.argv[3:]
cat_path = os.path.join(app, "OneScannerMac/Resources/Localizable.xcstrings")
src = json.load(open(os.path.join(tr, "source.json")))
cat = json.load(open(cat_path))
CATS = {l: ["one", "few", "many", "other"] for l in ["ru", "uk", "pl"]}
CATS.update({l: ["one", "other"] for l in ["de", "nl", "es", "pt-BR", "fr", "it", "tr"]})
NO_PLURALS = {"ja", "ko", "zh-Hans", "zh-Hant", "id", "vi"}

def ph(s):
    return sorted(re.sub(r"%\d+\$", "%", m) for m in re.findall(r"%(?:\d+\$)?(?:@|lld|ld|d)", s))

def unit(v):
    return {"stringUnit": {"state": "translated", "value": v}}

errors = []
for lang in langs:
    t = json.load(open(os.path.join(tr, lang + ".json")))
    for x in src:
        k = x["key"]
        if k not in t:
            errors.append((lang, "missing", k[:60])); continue
        v = t[k]
        if isinstance(v, dict) and (x["kind"] != "plural" or lang in NO_PLURALS):
            errors.append((lang, "plural forms where a plain string is expected", k[:60])); continue
        for f in (v.values() if isinstance(v, dict) else [v]):
            if ph(f) != ph(k):
                errors.append((lang, "placeholders", k[:60], f[:60]))
        entry = cat["strings"].setdefault(k, {}).setdefault("localizations", {})
        if isinstance(v, dict):
            if sorted(v) != sorted(CATS[lang]):
                errors.append((lang, "plural categories", k[:50], sorted(v)))
            entry[lang] = {"variations": {"plural": {c: unit(s) for c, s in v.items()}}}
        else:
            entry[lang] = unit(v)
if errors:
    print("not merged,", len(errors), "errors:")
    for e in errors[:60]:
        print(" ", e)
    sys.exit(1)
with open(cat_path, "w") as f:
    json.dump(cat, f, ensure_ascii=False, indent=2, separators=(",", " : "))
    f.write("\n")
print("merged", langs)
