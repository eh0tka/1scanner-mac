# Reviewing a 1Scanner translation

You are an independent native-level reviewer. Read INSTRUCTIONS.md (the translators' brief), source.json and
`glossary-<lang>.json`, then review `<lang>.json` key by key against the English key and its comment (search the key
in `OneScannerMac` for context, read only). Edit `<lang>.json` in place to fix:
- meaning errors and missing nuance; anything that sounds like a legal e-signature claim the English doesn't make;
- macOS terms that don't match Apple's own macOS localization in that language (Open…, Save As…, Show in Finder,
  Trash, Share…, Settings, Import from iPhone or iPad, Not Now…);
- the app's own terms drifting from 1Scanner for iPhone (`glossary-<lang>.json`) without a reason;
- inconsistent terms (the same English UI term translated differently in different keys);
- unnatural, machine-like or overly long wording, especially for buttons, badges, tool names and labels;
- grammar with numbers in plural forms (check every category reads correctly with e.g. 1, 2, 5, 21);
- placeholders: same multiset as the key; positional form only if reordered, and then for all placeholders.
Keep the JSON format exactly (see INSTRUCTIONS.md) and run the same validation script before finishing.
Report: number of keys changed, the most important fixes (up to 10, English key → old → new), and anything still
doubtful. Don't touch other languages' files.
