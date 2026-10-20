# 1Scanner for Mac — guide for contributors and coding agents

Read `docs/PRODUCT.md` (the product contract) first. The rules below protect people's documents and keep the product
behavior stable: don't change them without the maintainer's explicit approval.

## Product rules

- Free notarized DMG on onebuckapps.com only. Optional crypto support: the toolbar heart, and the Support sheet
  **once**, after the first useful result (first saved file or first code read; `AppModel.offerSupportOnce`), never
  again. **Tell a friend** (as in 1Scanner for iPhone; `AppModel.offerFriendIfDue`): a sheet from
  the third saved file, never in the session that offered support; after Not Now once more 30 days later, never
  after a share or a copy. It says why we ask and shows the exact message; nothing is sent unless the person picks
  where. Addresses live only in `Core/Donations.swift` and onebuckapps.com/donate/; only the maintainer changes them.
  Updates are checked only when the person asks, never in the background. *Install and Relaunch* (same as 1Cleaner for Mac; `Services/Updater.swift`), only on a click and never with unsaved changes:
  downloads the DMG `version.json` names (`dmg`, `sha256`), checks the hash, the bundle id, a higher build and a
  Developer ID signature of the same team as the running copy, puts the new app in its place (the old one goes to
  the Trash) and restarts. Whatever it can't do safely leaves the copy as it is and offers the website's Download.
- **No App Sandbox since 1.0.1**, so the app can replace itself. 1.0.0's signatures, stamps and
  settings are copied once from its container (`SandboxMigration`); the container is never changed.
- **The original is never changed.** Every result is a new file through a Save panel or into a picked folder; a file
  open in 1Scanner (or in the merge list) can't be replaced (`AppModel.isInUse`); split and export never overwrite
  (`AppModel.freeURL`). Unsaved changes are never dropped silently.
- Signatures and stamps: the person's own images, only on this Mac (`StampLibrary`, Application Support/Stamps),
  never uploaded; placed stamps are a separate layer until saving; copy never claims legal validity.
- Compression scales and re-encodes only pictures inside the PDF; text stays text. Only "Up to N MB" may turn pages
  into pictures, as its last resort, and then says text in that copy can't be selected. Sizes
  shown are always measured from the real file; it says so plainly when a limit can't be reached.
- QR: nothing opens by itself; links show the real site and warnings (`LinkCheck`, bundled public suffix list, no
  network lookup) before Open in Browser.
- No network except Check for Updates and Install and Relaunch, no analytics, account or third-party dependencies. Light appearance,
  1Scanner red (`Core/Theme.swift`), the line's header/footer copy.
- Not planned for now: editing PDF text, annotations, Word conversion, cloud, AI. Later candidates in `docs/PRODUCT.md`
  need the maintainer's yes.

## Architecture

- `OneScannerMac/App` — `@main` app and commands, `AppModel` (open files, pages, stamps on pages, saving, support,
  updates, thumbnails), `ToolModels` (merge list, QR results), `DebugLaunch`.
- `OneScannerMac/Core` — models (`PageItem`, `PageSource`, `StampPlacement`, `BuildPlan`), theme, donations, code
  parsing (`CodeContent`, `LinkCheck`, `CodeSymbology`, ported from iOS 1Scanner).
- `OneScannerMac/Services` — `PDFEngine` (an actor: every PDFKit job — opening, page pictures, building files with
  stamps, password and compression), `Compression` (ladder and "Up to N MB" search), `StampMaker` (paper removal,
  same as iOS), `ReadyStamps`, `StampLibrary`, `CodeReader` (Vision), `UpdateChecker`,
  `Updater` (Install and Relaunch) with `ProcessRunner` (hdiutil, ditto), `SandboxMigration` (in `StampLibrary.swift`).
- `OneScannerMac/Features` — SwiftUI screens. The Xcode project uses synchronized folders: new files compile
  automatically.
- A page is `PageSource` (file URL + index; an opened image is a one-page PDF in the engine) plus a quarter-turn and
  stamps. Pages without stamps are copied as they are (links and form fields kept); stamped pages are redrawn as one
  vector page with the stamps on top. Stamp coordinates are normalized on the page as shown (turn applied).
- Stamps go into a PDF at their placed size (300 dpi; less with compression) as a JPEG drawn through a transparency
  clip (`PDFEngine.compactStamp`), never as the library PNG: a PNG with alpha is stored losslessly and macOS's
  compression filter skips images with transparency (a seal was 0.8 MB). With compression, the pages go through the
  filter first and the stamps are added afterwards, so the filter can't re-encode them.
- Stamp handles (`PlacedStamp`) are separate views at the turned stamp's corners with a 36 pt hit area; never put a
  `contentShape` or `position` around them and the stamp together (that cut off their clicks).
- Nothing heavy on the main actor: PDF work runs in `PDFEngine`, Vision in detached tasks; long work shows the busy
  overlay with Cancel.
- Files come only from Open/Save panels, drops and Open With; the app reads nothing else of the person's (no folder
  scans). Signatures and stamps live in `~/Library/Application Support/1Scanner/Stamps`.

## Localization

- 17 languages since 1.1.0 (the same as 1Cleaner for Mac); About › Language overrides macOS's
  language for 1Scanner only (`Core/AppLanguage.swift`, after a restart). Every user-facing text is a SwiftUI literal
  or `String(localized:)`, one whole sentence per key, counts as `Int` interpolations. Strings live only in
  `OneScannerMac/Resources/Localizable.xcstrings`. New or changed strings ship translated and independently reviewed in
  all languages: follow `tools/l10n/README.md`.
- Website screenshots per language: `swift tools/make_demo_files.swift <qaDir>/in <lang>` (texts in
  `tools/demo_texts.json`), then the `-demoShots` run below with `-AppleLanguages "(<lang>)"`.

## Commands

- Build: `xcodebuild -project OneScannerMac.xcodeproj -scheme OneScannerMac -configuration Debug build`.
  There are no automated tests; check changes with the headless QA runs below.
- Headless QA (DEBUG): QA files live in `-qaDir <folder>` (default `~/Library/Caches/app.antosha.onescanner.mac/qa`).
  Put PDFs, `signature.*` (a photo of a signature) and `qr*` files into its `in/`, then run the built binary with
  `-qa YES`. It opens, signs, compresses, splits, merges, reads codes and exports into `out/` with a PNG per screen and
  `summary.txt`, then quits; at the end it removes its QA stamps and gives back the support offer and Tell a friend state it found.
  `-qaStamp YES` puts `signature.*` on page 1 of the first PDF, logs Original/Medium/Small/Up to 0.5 MB sizes and
  drives real mouse drags on the stamp, its resize and turn handles (`stamp.txt`, `stamp-handles.png`).
- Website screenshots (never real people's documents or signatures): `swift tools/make_demo_files.swift <dir>` (app folder)
  makes a made-up agreement, a seal and a signature photo, an invoice with QR codes; copy them into the QA folder's
  `in/`, then run the Debug binary with `-demoShots YES -isolatedStamps YES -compressUpTo YES
  -demoSelectStamp YES -demoSplitRanges "1-2, 3"`. It writes `out/demo-*.png` (2560×1600) with a throwaway
  stamp library; the site uses them at 1600×1000 as `1scanner-mac-*.jpg/.webp`.
- Release DMG: `SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" TEAM_ID=TEAMID tools/release.sh` →
  `build/dist/1Scanner-<version>-<build>.dmg`: universal, signed, notarized, stapled, checked with `spctl`.
  `--no-notarize` builds and signs without sending anything to Apple. Builds sign ad hoc by default, so anyone can
  build from source (README).
- Releases are published on onebuckapps.com: `version.json` names the new `version`, `build`, `dmg` URL and its
  `sha256`; that file is what Check for Updates and Install and Relaunch read.
- Install and Relaunch test (DEBUG, no network): build a signed DMG with `tools/release.sh --no-notarize`, write a
  local `version.json` with `"dmg": "file:///…dmg"` and its `sha256`, copy a Debug build made with
  `CURRENT_PROJECT_VERSION=<lower> CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="<the Developer ID identity>"
  DEVELOPMENT_TEAM=<team>` (Install and Relaunch refuses ad-hoc copies) into a writable folder and run it with `-installUpdate YES -updateFeed
  file:///…/version.json -qaDir <dir>`; `install.txt` holds the error, or stays `installing` when the copy relaunched. Quit the relaunched test copy
  by its PID, never with `pkill` (you may be running 1Scanner yourself).
