# 1Scanner for Mac — product contract

What the app does and the rules it keeps. Changes to this behavior need the maintainer's approval.

## Product

The Mac edition of 1Scanner: fast, human PDF work that Preview does badly — signatures and company seals from your
own library, compression to the size a website asks for, splitting by page ranges — plus reading QR codes from files.
Everything on the Mac: no account, no ads, no tracking, no server.

Decisions:

- **Name and brand:** 1Scanner, the Mac edition of 1Scanner for iPhone. The icon, the red `#E60C09` / `#B80306` and
  the look come from 1Scanner for iPhone. Bundle ID `app.antosha.onescanner.mac`. The name and icon are not covered
  by the code's license (see README).
- **Distribution and money:** free notarized DMG on onebuckapps.com only, like 1Cleaner for Mac. Optional crypto
  support: the heart at the top right, and the Support sheet **once, after the first useful result** (the first
  file 1Scanner saved, or the first QR code it read); never again after that. **Tell a friend**: a sheet from the third saved file, never in the session that offered support, once more 30 days
  after Not Now; Share… / Copy Message / Not Now with the exact message and the page link. Updates only when the person asks
  (About, app menu), from `onebuckapps.com/1scanner-mac/version.json`; since 1.0.1 **Install and Relaunch**
  downloads, verifies and installs the new version on a click (as in 1Cleaner for Mac).
- **Must have:** signatures and stamps from one's own library with the paper removed and **Add to All Pages**;
  split by page ranges; QR codes from files.
- **Not now:** editing PDF text, annotations and highlights, Word conversion, cloud, AI.

## 1.0 scope

| Area | What it does |
| --- | --- |
| Open | Drop PDFs or images on the window or the Dock icon, Open… (⌘O), Open With 1Scanner. Each PDF is its own file; images opened together become one new PDF, a page per image in name order (long side 842 pt). Locked PDFs ask for their password (kept only while the file is open). |
| Pages | Grid of pages: click, ⌘-click, ⇧-click select; drag to reorder; rotate left/right; delete (⌫); insert pages from other files (menu or drop on the grid); extract the selection as a new PDF; double-click opens Sign & Stamp on that page. |
| Save | **Save As…** always makes a new file through the Save panel (suggested "Name (signed)" / "Name (edited)" next to the original). The original is never changed, and a file open in 1Scanner can't be replaced. Unsaved changes are never dropped silently: closing a file asks Save As… / Don't Save / Cancel; quitting asks; closing the window keeps the app running. |
| Sign & Stamp | One page large, pages on the left, the library on the right. A click puts a signature or stamp on the page; drag moves it, the corner handle resizes it, the top handle (or the Angle slider) turns it, snapping to straight angles; ⌫ removes it; **Add to All Pages** puts it at the same spot on every page. Stamps stay a separate layer until saving draws them into the page (the page's own text stays text). Turning a page turns its stamps with it. |
| Signatures & Stamps library | From an image file, from the iPhone camera (File › Import from iPhone or iPad, Continuity Camera), drawn with the trackpad or mouse (blue or black), or ready stamps (APPROVED, PAID, COPY, CONFIDENTIAL, DRAFT, RECEIVED, the date; red, blue or black; optional today's date; your own word). The paper becomes transparent and the image is cropped to the ink (same algorithm as iOS). Stored only on this Mac in the app's Application Support; rename and delete. Copy never claims legal validity. |
| Compress | Original, Medium, Small and **Up to N MB** (0.2–20 MB stops, default 1 MB, then the last value), each with the size of the real file measured before saving. Original, Medium and Small scale down and re-encode only the pictures inside the PDF (macOS Quartz filter); text stays selectable. Up to N MB tries that first; when it can't fit, the pages become JPEG pictures (as on iPhone, and down to 700 px / JPEG 0.2 because a file that fits matters more than sharpness) and the sheet says text in that copy can't be selected or searched. If even that is too big: "Can't get under N MB. The smallest 1Scanner can make is X." Stamps go in at their placed size as JPEG with a transparency mask (a scanned seal adds ~0.1–0.2 MB, not its 0.8 MB PNG). |
| Split | By page ranges ("1-3, 5, 8-10", each range one file), every N pages, or page by page, into a folder the person picks; existing files are never replaced ("Name 1-3 2.pdf"). |
| Merge | Drop PDFs and images or add open files, drag rows into order, Merge… saves one PDF. Open files join as they are now (turns, removed pages, stamps). |
| Password | Save a copy protected with a password, or (for a PDF opened with its password) a copy without it. |
| Export images | Pages (selection or all) as PNG or JPEG at 100/200/300 dpi, stamps included, into a folder. |
| QR Codes | From pictures, screenshots pasted with ⌘V (or Paste) and every page of a PDF, with on-device Vision: QR, Micro QR, Aztec, Data Matrix, PDF417 and product/1D codes. Links show the full address with the real site highlighted and warnings (lookalikes, http, IP, shorteners; bundled public suffix list), open only on Open in Browser; Wi-Fi shows network and password with Copy; other content is shown and copied. Nothing opens by itself. Results live while the app runs. |
| About | Version, Check for Updates, support, Tell a friend, help & legal links, Follow us, other apps. |

Home shows the brand ("Private by design · 100% on-device"), a drop zone and tiles: Sign & Stamp, Compress, Merge,
Split, Read QR Codes, Images to PDF ("No ads. No tracking. No account." below).

## Technical contract

- macOS 14+, SwiftUI, PDFKit, Vision, Quartz filters; no third-party code, no analytics.
- Hardened runtime, Developer ID. **No App Sandbox since 1.0.1** so Install and Relaunch can
  replace the app; 1.0.0 was sandboxed and its data is copied over once. A Mac App Store edition (not decided) would
  need a sandboxed build without the updater.
- Languages (1.1.0): the 17 of 1Cleaner for Mac — en, ru, uk, de, nl, es, pt-BR, fr, it, pl, tr,
  ja, ko, zh-Hans, zh-Hant, id, vi. The app follows macOS's language; About › Language picks another one for 1Scanner
  only (after a restart, never over unsaved changes). Ready stamp words are in the app's language.

## Later candidates (not decided)

Make scanned PDFs (and pages turned into pictures) searchable (on-device text recognition), read codes from a screen area, QR generator, page numbers
and watermark, more languages, Mac App Store edition.
