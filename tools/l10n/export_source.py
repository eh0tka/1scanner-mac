"""export_source.py <app dir> <out dir> [--untranslated]: writes source.json for translators and, from 1Scanner for
iPhone's catalog, glossary-<lang>.json with its translations of the same English texts (a reference for consistent
terms; macOS wording still follows Apple's macOS).

Run `xcodebuild -exportLocalizations -project OneScannerMac.xcodeproj -localizationPath <dir> -exportLanguage en`
and `python3 tools/l10n/apply_en_plurals.py` first: they refresh the catalog from the code.
"""
import json, os, re, sys

LANGS = ["ru", "uk", "de", "nl", "es", "pt-BR", "fr", "it", "pl", "tr", "ja", "ko", "zh-Hans", "zh-Hant", "id", "vi"]
app, out = sys.argv[1], sys.argv[2]
catalog = json.load(open(os.path.join(app, "OneScannerMac/Resources/Localizable.xcstrings")))
only_new = "--untranslated" in sys.argv
source = []
for key, value in sorted(catalog["strings"].items()):
    if not key.strip() or value.get("shouldTranslate") is False:
        continue
    if only_new and len(value.get("localizations", {})) > 1:
        continue
    counts = len(re.findall(r"%(?:\d+\$)?lld", key))
    source.append({"key": key, "comment": value.get("comment", ""),
                   "kind": "plain" if counts == 0 else ("plural" if counts == 1 else "multi")})
os.makedirs(out, exist_ok=True)
json.dump(source, open(os.path.join(out, "source.json"), "w"), ensure_ascii=False, indent=1)
print(len(source), "strings →", os.path.join(out, "source.json"))

# 1Scanner for iPhone's catalog sits next to this app in the 1Buck Apps monorepo; without it there's no glossary.
ios_path = os.path.join(app, "../1scanner/OneScanner/Resources/Localizable.xcstrings")
if os.path.exists(ios_path):
    ios = json.load(open(ios_path))["strings"]
    def text(loc):
        if "stringUnit" in loc:
            return loc["stringUnit"]["value"]
        plural = loc.get("variations", {}).get("plural")
        return {k: v["stringUnit"]["value"] for k, v in plural.items()} if plural else None
    for lang in LANGS:
        glossary = {}
        for key, value in ios.items():
            loc = value.get("localizations", {}).get(lang)
            if loc and len(key) <= 120 and (t := text(loc)) is not None:
                glossary[key] = t
        json.dump(glossary, open(os.path.join(out, f"glossary-{lang}.json"), "w"), ensure_ascii=False, indent=1)
    print("glossaries from 1Scanner for iPhone:", len(LANGS))
