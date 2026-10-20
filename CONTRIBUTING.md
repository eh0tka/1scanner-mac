# Contributing

Thanks for helping make 1Scanner better.

**Issues are the best way to help:** a PDF that comes out wrong, a size limit that isn't met, a stamp that looks
off, a code that isn't read, a link warning that is missing or wrong. For anything that could damage or expose
documents, see [SECURITY.md](SECURITY.md).

**Pull requests** are welcome for small, focused changes, such as a fix in one tool or a translation fix. Please open
an issue first for anything bigger, so we can agree on the approach.

By submitting a pull request you agree that your contribution is licensed under GPL-3.0, and you grant the
maintainer the right to also distribute it under other terms (for example in an App Store build of 1Scanner).

Ground rules for code (details in [AGENTS.md](AGENTS.md)):
- The original file is never changed; every result is a new file and existing files are never replaced.
- Nothing heavy on the main thread: PDF work goes through `PDFEngine`.
- No analytics, accounts or third-party dependencies, and no network calls besides Check for Updates and Install and
  Relaunch, which run only when the person asks.
- Every user-facing text is localized (`String(localized:comment:)`); new strings need all 17 languages
  (`tools/l10n/README.md`).
- Copy never claims that a placed signature is legally valid.
