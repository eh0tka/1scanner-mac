import SwiftUI

/// Compress: Original, Medium, Small and "Up to N MB", each with the real size of the file it makes, measured on
/// this Mac before saving. Only pictures inside the PDF get smaller; text stays sharp and selectable.
struct CompressSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let file: OpenFile

    @State private var choice: Compression.Choice = Self.initialChoice
    @State private var results: [Compression.Choice: Data] = [:]
    @State private var fit: Compression.Fit?
    @State private var limitIndex = Self.storedLimitIndex
    @State private var measureTask: Task<Void, Never>?
    @State private var fitTask: Task<Void, Never>?
    @State private var errorText: String?

    private static var initialChoice: Compression.Choice {
        #if DEBUG
        // `-compressUpTo YES`: screenshots of the Up to N MB row.
        if UserDefaults.standard.bool(forKey: "compressUpTo") { return .upTo }
        #endif
        return .medium
    }

    private static var storedLimitIndex: Int {
        let stored = UserDefaults.standard.integer(forKey: Compression.limitKey)
        let value = stored > 0 ? stored : Compression.defaultLimit
        return Compression.limits.indices.min { abs(Compression.limits[$0] - value) < abs(Compression.limits[$1] - value) } ?? 4
    }

    private var limit: Int { Compression.limits[limitIndex] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Compress “\(file.name)”").font(.app(18, weight: .bold)).lineLimit(1)
                Text("Sizes are measured on this Mac: the file you save is exactly this size.")
                    .font(.app(12.5))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                row(.original, title: "Original", detail: "As it is now")
                row(.medium, title: "Medium", detail: "Sharp text, fits most email")
                row(.small, title: "Small", detail: "The smallest readable file")
                upToRow
            }
            if let errorText { NoteBanner(text: errorText, tone: .warning) }
            if let note = mostlyTextNote { NoteBanner(text: note) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save…", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(chosenData == nil)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear {
            measure()
            if choice == .upTo { refit() }
        }
        .onDisappear {
            measureTask?.cancel()
            fitTask?.cancel()
        }
        .onChange(of: choice) { _, new in if new == .upTo { refit() } }
        .onChange(of: limitIndex) {
            UserDefaults.standard.set(limit, forKey: Compression.limitKey)
            if choice == .upTo { refit() }
        }
    }

    private var chosenData: Data? {
        choice == .upTo ? fit?.data : results[choice]
    }

    /// Said when Small saves little: what's inside doesn't shrink while the text stays text.
    private var mostlyTextNote: String? {
        guard let original = results[.original], let small = results[.small],
              Double(small.count) > Double(original.count) * 0.85 else { return nil }
        return String(localized: "Pictures in this PDF can't get much smaller while it keeps its text. Up to N MB can turn the pages into pictures when that's the only way to fit.")
    }

    private func row(_ value: Compression.Choice, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        Button { choice = value } label: {
            HStack(spacing: 12) {
                Image(systemName: choice == value ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(choice == value ? Theme.accent : Theme.secondaryText)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.app(14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(.app(12)).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if let data = results[value] {
                    Text(Int64(data.count).formattedBytes).font(.appNumber(15, weight: .semibold)).monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)
            .background(choice == value ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var upToRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { choice = .upTo } label: {
                HStack(spacing: 12) {
                    Image(systemName: choice == .upTo ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(choice == .upTo ? Theme.accent : Theme.secondaryText)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Up to \(Compression.limitTitle(limit))").font(.app(14, weight: .semibold)).foregroundStyle(Theme.text)
                        Text("For websites and forms with a size limit").font(.app(12)).foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    if choice == .upTo {
                        if let fit {
                            Text(Int64(fit.data.count).formattedBytes).font(.appNumber(15, weight: .semibold)).monospacedDigit()
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if choice == .upTo {
                Slider(value: Binding(get: { Double(limitIndex) }, set: { limitIndex = Int($0.rounded()) }),
                       in: 0...Double(Compression.limits.count - 1), step: 1) {
                    Text("Limit")
                } minimumValueLabel: {
                    Text(Compression.limitTitle(Compression.limits[0])).font(.app(11))
                } maximumValueLabel: {
                    Text(Compression.limitTitle(Compression.limits[Compression.limits.count - 1])).font(.app(11))
                }
                .labelsHidden()
                if let fit, fit.pagesAsPictures {
                    Label("To fit, the pages became pictures: text in this copy can't be selected or searched. The original keeps its text.",
                          systemImage: "photo")
                        .font(.app(12))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let fit, !fit.reached {
                    Text("Can't get under \(Compression.limitTitle(limit)). The smallest 1Scanner can make is \(Int64(fit.data.count).formattedBytes).")
                        .font(.app(12))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
        .background(choice == .upTo ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline))
    }

    private func plan(_ step: CompressionStep?) -> BuildPlan {
        model.plan(file.pages, password: file.password, quality: step)
    }

    private func measure() {
        let steps: [(Compression.Choice, CompressionStep?)] = [(.original, nil), (.medium, Compression.medium), (.small, Compression.small)]
        let plans = steps.map { ($0.0, plan($0.1)) }
        measureTask = Task {
            for (value, plan) in plans {
                do {
                    let data = try await PDFEngine.shared.build(plan)
                    results[value] = data
                } catch is CancellationError {
                    return
                } catch {
                    errorText = error.localizedDescription
                    return
                }
            }
        }
    }

    private func refit() {
        fitTask?.cancel()
        fit = nil
        let limit = limit
        let known = results
        let medium = Compression.medium, small = Compression.small
        let base = plan(nil)
        fitTask = Task {
            do {
                let result = try await Compression.fit(limit: limit) { step in
                    if step == nil, let data = known[.original] { return data }
                    if step == medium, let data = known[.medium] { return data }
                    if step == small, let data = known[.small] { return data }
                    var plan = base
                    plan.quality = step
                    return try await PDFEngine.shared.build(plan)
                }
                guard !Task.isCancelled else { return }
                fit = result
            } catch is CancellationError {
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func save() {
        guard let data = chosenData else { return }
        let name = "\(file.name) (\(Int64(data.count).formattedBytes))"
        dismiss()
        Task { model.save(data, name: name, near: file.url) }
    }
}

/// Split: by page ranges ("1-3, 5, 8-10", each range one file), every N pages, or page by page, into a folder.
struct SplitSheet: View {
    enum Mode: Hashable { case ranges, every, each }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let file: OpenFile
    @State private var mode: Mode = .ranges
    @State private var rangesText = ""
    @State private var every = 2

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Split “\(file.name)”").font(.app(18, weight: .bold)).lineLimit(1)
            Picker("Split", selection: $mode) {
                Text("By page ranges").tag(Mode.ranges)
                Text("Every few pages").tag(Mode.every)
                Text("Page by page").tag(Mode.each)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch mode {
            case .ranges:
                VStack(alignment: .leading, spacing: 6) {
                    TextField("For example: 1-3, 5, 8-10", text: $rangesText)
                        .textFieldStyle(.roundedBorder)
                        .font(.app(14))
                    Text("Each range becomes its own PDF. Pages 1 to \(file.pages.count).")
                        .font(.app(12))
                        .foregroundStyle(Theme.secondaryText)
                }
            case .every:
                Stepper(value: $every, in: 1...max(1, file.pages.count)) {
                    Text("A new file every \(every) pages").font(.app(14))
                }
            case .each:
                Text("Each of the \(file.pages.count) pages becomes its own PDF.").font(.app(14))
            }
            summary
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Split…", action: split)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled((ranges?.isEmpty ?? true))
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear {
            // Selected pages as the first suggestion.
            let selected = file.pages.enumerated().filter { file.selection.contains($0.element.id) }.map { $0.offset + 1 }
            if !selected.isEmpty { rangesText = PageRanges.describe(selected) }
            #if DEBUG
            // `-demoSplitRanges "1-2, 3"`: website screenshots.
            if let demo = UserDefaults.standard.string(forKey: "demoSplitRanges") { rangesText = demo }
            #endif
        }
    }

    private var ranges: [ClosedRange<Int>]? {
        let count = file.pages.count
        switch mode {
        case .ranges:
            return PageRanges.parse(rangesText, count: count)
        case .every:
            return stride(from: 1, through: count, by: every).map { $0...min($0 + every - 1, count) }
        case .each:
            return (1...max(count, 1)).map { $0...$0 }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let ranges, !ranges.isEmpty {
            let names = ranges.prefix(6).map(Self.title).joined(separator: ", ") + (ranges.count > 6 ? "…" : "")
            Label("Makes \(ranges.count) files: \(names)", systemImage: "doc.on.doc")
                .font(.app(13, weight: .medium))
                .foregroundStyle(Theme.accentDeep)
        } else if mode == .ranges, !rangesText.trimmingCharacters(in: .whitespaces).isEmpty {
            Label("Use page numbers from 1 to \(file.pages.count), like 1-3, 5.", systemImage: "exclamationmark.circle")
                .font(.app(13))
                .foregroundStyle(Theme.danger)
        }
    }

    private static func title(_ range: ClosedRange<Int>) -> String {
        range.count == 1 ? "\(range.lowerBound)" : "\(range.lowerBound)-\(range.upperBound)"
    }

    private func split() {
        guard let ranges, !ranges.isEmpty else { return }
        let parts = ranges.map { range in
            (name: "\(file.name) \(Self.title(range))", ext: "pdf")
        }
        let plans = ranges.map { range in
            model.plan(file.pages[(range.lowerBound - 1)...(range.upperBound - 1)].map { $0.duplicated() }, password: file.password)
        }
        dismiss()
        Task {
            model.writeFiles(parts, near: file.url, prompt: String(localized: "Split Here"), title: String(localized: "Splitting…")) { index in
                try await PDFEngine.shared.build(plans[index])
            }
        }
    }
}

/// A copy with a password, or without it. The open file and the original stay as they are.
struct PasswordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let file: OpenFile
    @State private var password = ""
    @State private var repeated = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Password").font(.app(18, weight: .bold))
            if file.password != nil {
                Text("“\(file.name)” is protected with a password. Save a copy that opens without it, or a copy with a new one.")
                    .font(.app(13))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Save a Copy without Password…") { saveCopy(password: nil) }
                    .buttonStyle(SecondaryButtonStyle())
                Divider()
            } else {
                Text("Save a copy that asks for this password to open. Keep it somewhere safe: it can't be recovered.")
                    .font(.app(13))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SecureField(file.password == nil ? "Password" : "New password", text: $password)
                .textFieldStyle(.roundedBorder)
            SecureField("Repeat password", text: $repeated)
                .textFieldStyle(.roundedBorder)
            if !repeated.isEmpty, password != repeated {
                Text("The passwords don't match.").font(.app(12)).foregroundStyle(Theme.danger)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Protected Copy…") { saveCopy(password: password) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(password.isEmpty || password != repeated)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func saveCopy(password: String?) {
        let suffix = password == nil ? String(localized: "no password") : String(localized: "protected")
        let plan = model.plan(file.pages, password: password)
        dismiss()
        Task {
            guard let url = model.chooseSaveURL(name: "\(file.name) (\(suffix))", near: file.url) else { return }
            model.write(plan, to: url, title: String(localized: "Saving…"))
        }
    }
}

/// Pages as PNG or JPEG pictures in a folder, stamps included.
struct ExportImagesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let file: OpenFile
    @AppStorage("export.jpeg") private var jpeg = false
    @AppStorage("export.dpi") private var dpi = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Pages as Images").font(.app(18, weight: .bold))
            Group {
                if file.selection.isEmpty {
                    Text("All \(file.pages.count) pages.")
                } else {
                    Text("The \(file.selection.count) selected pages.")
                }
            }
            .font(.app(13))
            .foregroundStyle(Theme.secondaryText)
            Picker("Format", selection: $jpeg) {
                Text("PNG").tag(false)
                Text("JPEG").tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Picker("Resolution", selection: $dpi) {
                Text("Screen (100 dpi)").tag(100)
                Text("Good (200 dpi)").tag(200)
                Text("Print (300 dpi)").tag(300)
            }
            .fixedSize()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…", action: export)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func export() {
        let pages = file.selectedPages
        let numbers = pages.compactMap { page in file.pages.firstIndex { $0.id == page.id }.map { $0 + 1 } }
        let parts = numbers.map { (name: "\(file.name) \(String(localized: "page")) \($0)", ext: jpeg ? "jpg" : "png") }
        let plan = model.plan(pages, password: nil)
        let dpi = Double(dpi), jpeg = jpeg
        let made = PicturesBox()
        dismiss()
        Task {
            model.writeFiles(parts, near: file.url, prompt: String(localized: "Export Here"), title: String(localized: "Exporting…")) { index in
                if made.pictures == nil {
                    made.pictures = try await PDFEngine.shared.pictures(plan, dpi: dpi, jpeg: jpeg)
                }
                return made.pictures?[index] ?? Data()
            }
        }
    }
}

/// The page pictures, made once for all files of an export.
@MainActor
private final class PicturesBox {
    var pictures: [Data]?
}
