# Translating 1Scanner for Mac

1Scanner for Mac is a free PDF tool for everyone: open PDFs and images, put one's own signature, initials or company
seal (made from a photo, paper removed) on a page or on every page, ready stamps (APPROVED, PAID…), compress to a
size limit, split by page ranges, merge, reorder/rotate/delete/extract pages, add or remove a password, and read QR
codes and barcodes from pictures, screenshots and PDFs. Everything stays on the Mac. Free, with optional crypto
support for the developer.

Input: `source.json` — a list of {key, comment, kind}. `key` is the English source text; `comment` (often empty)
says where it shows. For context, search the key in the app's code: `OneScannerMac` (read only).

Reference: `glossary-<lang>.json` holds 1Scanner for iPhone's translations of the same English texts. Reuse its terms
for the app's own concepts (Signatures & Stamps, ready stamp words, Add to All Pages, compression levels, QR code
types…) unless they are iPhone-specific or wrong for macOS. Words that are macOS UI must follow Apple's macOS
localization instead.

Output: one file `<lang>.json` (lang code exactly: ru, uk, de, nl, es, pt-BR, fr, it, pl, tr, ja, ko, zh-Hans,
zh-Hant, id, vi): a JSON object mapping EVERY key of source.json to its translation:
- kind "plain": a string.
- kind "plural" (one integer `%lld`): an object with the plural categories of the language, each a full string
  with the same placeholders: ru, uk, pl: {"one", "few", "many", "other"}; de, nl, es, pt-BR, fr, it, tr:
  {"one", "other"}; ja, ko, zh-Hans, zh-Hant, id, vi: a plain string (no plural forms).
- kind "multi" (two or more integers): a plain string; phrase it so no word must agree with a number.
Write valid UTF-8 JSON (no comments, no trailing commas).

Placeholders (`%@`, `%lld`, `%1$@`, …) must stay exactly as in the key, same count and types. If your word order needs
them in a different order, switch EVERY placeholder in that string to positional form (`%1$@`, `%2$lld`, …) numbered
by their order in the English key. Keep `…` (one character), `·` separators, typographic quotes as your language
uses them (« », „ “, 「」…), newlines, and the punctuation style.

Never translate: 1Scanner, 1Cleaner, 1Buck Apps, brand names (iPhone, iPad, Continuity Camera, Finder, Telegram,
YouTube, TikTok, X), code symbology names (QR, EAN-13, Code 128, PDF417, Data Matrix, Aztec…), crypto networks and
coins, file formats (PDF, PNG, JPEG), "onebuckapps.com".

macOS words must match Apple's own macOS localization in your language exactly: Open…, Save As…, Close, Show in
Finder, Trash, Move to Trash, Share…, Copy, Paste, Undo, Settings, Quit, Import from iPhone or iPad, Take Photo, Scan
Documents, Done, Cancel, OK, Not Now. Ready stamp words (APPROVED, PAID, COPY, CONFIDENTIAL, DRAFT, RECEIVED) are
printed on documents: use what offices in your language stamp, in capitals, short.

Style: plain, short, friendly, like Apple's own UI text. Buttons and badges as short as possible. No marketing words.
Never make a legal claim the English doesn't (signatures here are pictures, not legally valid e-signatures).

Before finishing: run a script that loads source.json and your file and checks (1) every key is present, (2) for
every string/form the multiset of placeholders equals the key's (treat `%1$@` as `%@` etc.), (3) plural objects have
exactly the categories listed above. Fix until clean. Report any key you were unsure about.
