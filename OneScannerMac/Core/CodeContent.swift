import Foundation

/// What a code contains, read from its text (docs/PRODUCT.md §4.8). Parsing only; nothing here opens or sends
/// anything.
enum CodeContent: Hashable, Sendable {
    case link(URL)
    case wifi(WiFi)
    case contact(Contact)
    case event(Event)
    case phone(String)
    case sms(number: String, body: String?)
    case email(address: String, subject: String?, body: String?)
    case location(latitude: Double, longitude: Double, query: String?)
    case product(number: String, kind: ProductKind)
    case text(String)

    struct WiFi: Hashable, Sendable {
        let ssid: String
        let password: String?
        /// "WPA", "WEP", "nopass", or empty.
        let security: String
        let isHidden: Bool

        var isOpen: Bool { security.isEmpty || security.lowercased() == "nopass" || password?.isEmpty != false }
    }

    struct Contact: Hashable, Sendable {
        /// A vCard (MECARD codes are converted), for the system's contact screen.
        let vCard: String
        let name: String?
        let phones: [String]
        let emails: [String]
        let organization: String?
    }

    struct Event: Hashable, Sendable {
        let title: String?
        let start: Date?
        let end: Date?
        let location: String?
        let isAllDay: Bool
    }

    enum ProductKind: String, Hashable, Sendable {
        case ean13, ean8, upcA, upcE, isbn

        var displayName: String {
            switch self {
            case .ean13: "EAN-13"
            case .ean8: "EAN-8"
            case .upcA: "UPC-A"
            case .upcE: "UPC-E"
            case .isbn: "ISBN"
            }
        }
    }

    // MARK: Parsing

    static func parse(_ payload: String, symbology: CodeSymbology) -> CodeContent {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if let product = product(text, symbology: symbology) { return product }
        let upper = text.uppercased()
        if upper.hasPrefix("WIFI:"), let wifi = wifi(text) { return .wifi(wifi) }
        if upper.hasPrefix("BEGIN:VCARD"), let contact = contact(vCard: text) { return .contact(contact) }
        if upper.hasPrefix("MECARD:"), let contact = contact(meCard: text) { return .contact(contact) }
        if upper.contains("BEGIN:VEVENT"), let event = event(text) { return .event(event) }
        if upper.hasPrefix("TEL:") { return .phone(String(text.dropFirst(4))) }
        if upper.hasPrefix("SMSTO:") || upper.hasPrefix("SMS:") { return sms(text) }
        if upper.hasPrefix("MAILTO:") { return mailto(text) }
        if upper.hasPrefix("MATMSG:") { return matmsg(text) }
        if upper.hasPrefix("GEO:"), let location = geo(text) { return location }
        if let url = webLink(text) { return .link(url) }
        return .text(text)
    }

    /// http and https only; "www.example.com" is read as https. Other schemes stay text and never open.
    private static func webLink(_ text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        let lower = text.lowercased()
        let candidate: String
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            candidate = text
        } else if lower.hasPrefix("www."), text.contains(".") {
            candidate = "https://" + text
        } else {
            return nil
        }
        guard let url = URL(string: candidate), let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        return url
    }

    private static func product(_ text: String, symbology: CodeSymbology) -> CodeContent? {
        guard text.allSatisfy(\.isNumber) else { return nil }
        switch symbology {
        case .ean13 where text.count == 13:
            if text.hasPrefix("978") || text.hasPrefix("979") { return .product(number: text, kind: .isbn) }
            if text.hasPrefix("0") { return .product(number: String(text.dropFirst()), kind: .upcA) }
            return .product(number: text, kind: .ean13)
        case .ean8 where text.count == 8:
            return .product(number: text, kind: .ean8)
        case .upce where text.count == 8 || text.count == 6:
            return .product(number: text, kind: .upcE)
        default:
            return nil
        }
    }

    /// `WIFI:T:WPA;S:name;P:secret;H:false;;` with `\` escaping `;`, `,`, `:` and `\`.
    private static func wifi(_ text: String) -> WiFi? {
        let fields = meFields(String(text.dropFirst(5)))
        guard let ssid = fields["S"], !ssid.isEmpty else { return nil }
        return WiFi(
            ssid: ssid,
            password: fields["P"],
            security: fields["T"] ?? "",
            isHidden: (fields["H"] ?? "").lowercased() == "true"
        )
    }

    /// `KEY:value;KEY:value;` fields (Wi-Fi, MECARD, MATMSG); a key may repeat (all values joined by "\n").
    private static func meFields(_ body: String) -> [String: String] {
        var fields: [String: String] = [:]
        var key = ""
        var value = ""
        var readingKey = true
        var escaped = false
        func finish() {
            let trimmedKey = key.trimmingCharacters(in: .whitespaces).uppercased()
            if !trimmedKey.isEmpty {
                fields[trimmedKey] = fields[trimmedKey].map { $0 + "\n" + value } ?? value
            }
            key = ""
            value = ""
            readingKey = true
        }
        for character in body {
            if escaped {
                if readingKey { key.append(character) } else { value.append(character) }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if readingKey, character == ":" {
                readingKey = false
            } else if !readingKey, character == ";" {
                finish()
            } else if readingKey {
                key.append(character)
            } else {
                value.append(character)
            }
        }
        if !readingKey { finish() }
        return fields
    }

    private static func contact(vCard: String) -> Contact? {
        var name: String?
        var structuredName: String?
        var phones: [String] = []
        var emails: [String] = []
        var organization: String?
        for line in unfoldedLines(vCard) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].uppercased()
            let value = String(line[line.index(after: colon)...]).replacingOccurrences(of: "\\,", with: ",")
            let property = key.split(separator: ";").first.map(String.init) ?? key
            switch property {
            case "FN": name = value
            case "N":
                let parts = value.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
                structuredName = [parts.count > 1 ? parts[1] : "", parts.first ?? ""]
                    .filter { !$0.isEmpty }.joined(separator: " ")
            case "TEL": phones.append(value)
            case "EMAIL": emails.append(value)
            case "ORG": organization = value.replacingOccurrences(of: ";", with: " ").trimmingCharacters(in: .whitespaces)
            default: break
            }
        }
        let displayName = (name?.isEmpty == false ? name : structuredName).flatMap { $0.isEmpty ? nil : $0 }
        guard displayName != nil || !phones.isEmpty || !emails.isEmpty else { return nil }
        return Contact(vCard: vCard, name: displayName, phones: phones, emails: emails, organization: organization)
    }

    /// `MECARD:N:Doe,John;TEL:123;EMAIL:a@b.c;;`, converted to a vCard for the system's contact screen.
    private static func contact(meCard text: String) -> Contact? {
        let fields = meFields(String(text.dropFirst(7)))
        let nameParts = (fields["N"] ?? "").split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let name = nameParts.count == 2 ? "\(nameParts[1]) \(nameParts[0])" : nameParts.first
        let phones = (fields["TEL"] ?? "").split(separator: "\n").map(String.init)
        let emails = (fields["EMAIL"] ?? "").split(separator: "\n").map(String.init)
        guard name?.isEmpty == false || !phones.isEmpty || !emails.isEmpty else { return nil }
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        if let name, !name.isEmpty {
            lines.append("FN:\(name)")
            lines.append("N:\(nameParts.first ?? "");\(nameParts.count == 2 ? nameParts[1] : "");;;")
        }
        if let org = fields["ORG"] { lines.append("ORG:\(org)") }
        phones.forEach { lines.append("TEL:\($0)") }
        emails.forEach { lines.append("EMAIL:\($0)") }
        if let url = fields["URL"] { lines.append("URL:\(url)") }
        if let address = fields["ADR"] { lines.append("ADR:;;\(address);;;;") }
        if let note = fields["NOTE"] { lines.append("NOTE:\(note)") }
        lines.append("END:VCARD")
        return Contact(
            vCard: lines.joined(separator: "\r\n"),
            name: name?.isEmpty == false ? name : nil,
            phones: phones,
            emails: emails,
            organization: fields["ORG"]
        )
    }

    private static func event(_ text: String) -> Event? {
        var title: String?
        var location: String?
        var start: Date?
        var end: Date?
        var allDay = false
        var inEvent = false
        for line in unfoldedLines(text) {
            let upper = line.uppercased()
            if upper.hasPrefix("BEGIN:VEVENT") { inEvent = true; continue }
            if upper.hasPrefix("END:VEVENT") { break }
            guard inEvent, let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].uppercased()
            let value = String(line[line.index(after: colon)...]).replacingOccurrences(of: "\\,", with: ",")
            if key.hasPrefix("SUMMARY") { title = value }
            if key.hasPrefix("LOCATION") { location = value }
            if key.hasPrefix("DTSTART") {
                start = icsDate(value)
                allDay = key.contains("VALUE=DATE") || value.count == 8
            }
            if key.hasPrefix("DTEND") { end = icsDate(value) }
        }
        guard title != nil || start != nil else { return nil }
        return Event(title: title, start: start, end: end, location: location, isAllDay: allDay)
    }

    private static func icsDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for (format, utc) in [("yyyyMMdd'T'HHmmss'Z'", true), ("yyyyMMdd'T'HHmmss", false), ("yyyyMMdd", false)] {
            formatter.dateFormat = format
            formatter.timeZone = utc ? TimeZone(identifier: "UTC") : .current
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    /// vCard and iCalendar lines, with folded continuation lines joined.
    private static func unfoldedLines(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.components(separatedBy: CharacterSet.newlines) where !raw.isEmpty {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), let last = lines.popLast() {
                lines.append(last + raw.dropFirst())
            } else {
                lines.append(raw)
            }
        }
        return lines
    }

    /// `SMSTO:number:message` or `sms:number?body=message`.
    private static func sms(_ text: String) -> CodeContent {
        if text.uppercased().hasPrefix("SMSTO:") {
            let parts = text.dropFirst(6).split(separator: ":", maxSplits: 1).map(String.init)
            return .sms(number: parts.first ?? "", body: parts.count > 1 ? parts[1] : nil)
        }
        let rest = String(text.dropFirst(4))
        let components = URLComponents(string: "sms:" + rest)
        let number = rest.split(separator: "?").first.map(String.init) ?? rest
        let body = components?.queryItems?.first { $0.name.lowercased() == "body" }?.value
        return .sms(number: number, body: body)
    }

    private static func mailto(_ text: String) -> CodeContent {
        let components = URLComponents(string: text)
        let address = components?.path ?? String(text.dropFirst(7))
        let items = components?.queryItems ?? []
        let subject = items.first { $0.name.lowercased() == "subject" }?.value
        let body = items.first { $0.name.lowercased() == "body" }?.value
        return .email(address: address.removingPercentEncoding ?? address, subject: subject, body: body)
    }

    /// `MATMSG:TO:a@b.c;SUB:subject;BODY:text;;`
    private static func matmsg(_ text: String) -> CodeContent {
        let fields = meFields(String(text.dropFirst(7)))
        return .email(address: fields["TO"] ?? "", subject: fields["SUB"], body: fields["BODY"])
    }

    /// `geo:40.4168,-3.7038` or `geo:40.4,-3.7?q=Madrid`.
    private static func geo(_ text: String) -> CodeContent? {
        let rest = text.dropFirst(4)
        let coordinates = rest.split(separator: "?", maxSplits: 1).first ?? rest[...]
        let numbers = coordinates.split(separator: ",").compactMap { Double($0.split(separator: ";").first ?? "") }
        guard numbers.count >= 2, abs(numbers[0]) <= 90, abs(numbers[1]) <= 180 else { return nil }
        let query = URLComponents(string: "geo:x?" + (rest.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""))?
            .queryItems?.first { $0.name == "q" }?.value
        return .location(latitude: numbers[0], longitude: numbers[1], query: query)
    }
}
