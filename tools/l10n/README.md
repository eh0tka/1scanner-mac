# 1Scanner Mac localization

17 languages (the same as 1Cleaner for Mac): en, ru, uk, de, nl, es, pt-BR, fr, it, pl, tr, ja,
ko, zh-Hans, zh-Hant, id, vi. The app follows macOS's language; About › Language overrides it for 1Scanner only
(`Core/AppLanguage.swift`, applies after a restart). Translations live only in
`OneScannerMac/Resources/Localizable.xcstrings`.

Rules for code: every user-facing text is a SwiftUI literal or `String(localized: "…", comment: "…")`, one whole
sentence per key, counts as `Int` interpolations (plural forms in the catalog), no logic on displayed text. Never
localize paths, ids, code symbology names (EAN-13, Code 128), crypto networks or brand names.

Adding or changing strings (run from the app folder):
1. `xcodebuild -exportLocalizations -project OneScannerMac.xcodeproj -localizationPath /tmp/l10n -exportLanguage en`
   then `python3 tools/l10n/apply_en_plurals.py` (new English singulars go to `en_plurals.json`).
2. `python3 tools/l10n/export_source.py . /tmp/tr --untranslated` → `source.json` with the new keys and
   `glossary-<lang>.json` (1Scanner for iPhone's translations of the same English texts).
3. Translate per language following `INSTRUCTIONS.md` (one translator per language), then an independent reviewer
   per language following `REVIEW.md` (every generated text is reviewed by a separate LLM).
4. `python3 tools/l10n/merge.py . /tmp/tr ru uk de nl es pt-BR fr it pl tr ja ko zh-Hans zh-Hant id vi` — fails
   loudly on missing keys, placeholder mismatches and wrong plural categories.
5. Check screens with `-AppleLanguages "(de)"` and the demo QA run (German is the longest, Japanese and Chinese the
   narrowest).
