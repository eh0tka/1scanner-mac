import Foundation

/// What a link from a code really points to, and what may be a trick (docs/PRODUCT.md §4.8). All on the device from
/// the text itself; nothing is looked up. The warnings are honest hints, not a verdict: Safari's own fraud warning
/// still applies when the link is opened.
struct LinkCheck: Hashable, Sendable {
    enum Warning: Hashable, Sendable {
        /// The address isn't encrypted (http).
        case plainHTTP
        /// A bare IP number instead of a site name.
        case ipAddress
        /// `https://paypal.com@evil.top`: the part before @ is not the site.
        case userInfo(String)
        /// Letters from different alphabets in one name (a Cyrillic "а" among Latin letters).
        case mixedScripts
        /// Special characters that can imitate another name (`xn--…`).
        case internationalName
        /// Looks like a known brand but isn't: "paypa1.com".
        case lookalike(brand: String)
        /// A known brand in the address while the real site is another one.
        case brandInAddress(brand: String, realSite: String)
        /// A link shortener hides where it leads.
        case shortener
    }

    let url: URL
    /// The full address as shown (international names decoded).
    let displayAddress: String
    /// The host as shown.
    let host: String
    /// The real site: the registrable domain ("secure-login.top").
    let realSite: String
    let warnings: [Warning]

    init(url: URL, rawText: String? = nil) {
        self.url = url
        let asciiHost = (url.host(percentEncoded: false) ?? "").lowercased()
        let decodedHost = asciiHost.split(separator: ".").map { Self.decodeLabel(String($0)) }.joined(separator: ".")
        // Hosts written in Unicode inside the code are checked as written.
        let rawHost = rawText.flatMap(Self.rawHost(of:))?.lowercased()
        let shownHost = rawHost.flatMap { $0.unicodeScalars.contains { !$0.isASCII } ? $0 : nil } ?? decodedHost
        host = shownHost
        realSite = Self.isIPAddress(asciiHost) ? shownHost : Self.registrableDomain(of: shownHost)
        let text = url.absoluteString
        displayAddress = text.replacingOccurrences(of: asciiHost, with: shownHost, options: .caseInsensitive, range: text.range(of: asciiHost, options: .caseInsensitive))

        var warnings: [Warning] = []
        if url.scheme?.lowercased() == "http" { warnings.append(.plainHTTP) }
        if Self.isIPAddress(asciiHost) { warnings.append(.ipAddress) }
        if let user = url.user(percentEncoded: false), !user.isEmpty { warnings.append(.userInfo(user)) }
        if asciiHost.split(separator: ".").contains(where: { $0.hasPrefix("xn--") }) || shownHost.unicodeScalars.contains(where: { !$0.isASCII }) {
            warnings.append(Self.hasMixedScripts(shownHost) ? .mixedScripts : .internationalName)
        }
        if Self.shorteners.contains(realSite) { warnings.append(.shortener) }
        if !Self.isIPAddress(asciiHost), let brandWarning = Self.brandWarning(host: shownHost, realSite: realSite) {
            warnings.append(brandWarning)
        }
        self.warnings = warnings
    }

    // MARK: Domains

    /// Both ICANN and private suffixes, including wildcard and exception rules. Bundled; no network lookup.
    static func registrableDomain(of host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 1, !suffixRules.isEmpty else { return host }
        var suffixCount = 1
        for index in labels.indices {
            let suffix = labels[index...].joined(separator: ".")
            if suffixRules.contains("!" + suffix) {
                return labels.suffix(labels.count - index).joined(separator: ".")
            }
            if suffixRules.contains(suffix) { suffixCount = max(suffixCount, labels.count - index) }
            if index + 1 < labels.count,
               suffixRules.contains("*." + labels[(index + 1)...].joined(separator: ".")) {
                suffixCount = max(suffixCount, labels.count - index)
            }
        }
        return labels.suffix(min(labels.count, suffixCount + 1)).joined(separator: ".")
    }

    private static let suffixRules: Set<String> = {
        guard let url = Bundle.main.url(forResource: "public_suffix_list", withExtension: "dat"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").compactMap { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty || value.hasPrefix("//") ? nil : value.lowercased()
        })
    }()

    static let shorteners: Set<String> = [
        "bit.ly", "bitly.com", "tinyurl.com", "t.co", "goo.gl", "ow.ly", "is.gd", "buff.ly", "cutt.ly", "rebrand.ly",
        "shorturl.at", "rb.gy", "t.ly", "tiny.cc", "lnkd.in", "s.id", "v.gd", "bl.ink", "short.io", "qrco.de",
        "qr.io", "tr.ee", "shorturl.gg", "u.to", "x.co", "trib.al", "dlvr.it", "surl.li", "clck.ru", "bit.do"
    ]

    /// Brands phishing codes imitate most: payments, banks, shops, mail and delivery.
    static let brands: [String] = [
        "paypal", "apple", "icloud", "google", "gmail", "microsoft", "outlook", "office365", "amazon",
        "netflix", "facebook", "instagram", "whatsapp", "telegram", "tiktok", "linkedin", "twitter", "spotify",
        "adobe", "dropbox", "ebay", "walmart", "mercadolibre", "mercadopago", "dhl", "fedex", "ups", "usps",
        "correos", "santander", "bbva", "caixabank", "sabadell", "bankinter", "ing", "chase", "wellsfargo",
        "bankofamerica", "citibank", "hsbc", "barclays", "revolut", "wise", "coinbase", "binance", "steam",
        "banorte", "banamex", "bancomer", "hacienda"
    ]

    /// How a brand is written ("PayPal", "iCloud").
    static func brandName(_ brand: String) -> String {
        let special: [String: String] = [
            "paypal": "PayPal", "icloud": "iCloud", "whatsapp": "WhatsApp", "tiktok": "TikTok", "linkedin": "LinkedIn",
            "office365": "Office 365", "ebay": "eBay", "mercadolibre": "Mercado Libre", "mercadopago": "Mercado Pago",
            "dhl": "DHL", "fedex": "FedEx", "ups": "UPS", "usps": "USPS", "bbva": "BBVA", "ing": "ING", "hsbc": "HSBC",
            "caixabank": "CaixaBank", "wellsfargo": "Wells Fargo", "bankofamerica": "Bank of America"
        ]
        return special[brand] ?? brand.prefix(1).uppercased() + brand.dropFirst()
    }

    /// A brand appearing in the address (as a name part) while the real site isn't that brand's; or a lookalike.
    private static func brandWarning(host: String, realSite: String) -> Warning? {
        let siteName = realSite.split(separator: ".").first.map(String.init) ?? realSite
        // The brand's own site ("mail.google.com", "amazon.es").
        if brands.contains(siteName) { return nil }
        let tokens = host.split(whereSeparator: { $0 == "." || $0 == "-" }).map(String.init)
        if let brand = brands.first(where: { tokens.contains($0) }) {
            return .brandInAddress(brand: brand, realSite: realSite)
        }
        // "paypa1", "g00gle", "arnazon": look-alike spellings of the site's own name.
        let normalized = siteName
            .replacingOccurrences(of: "rn", with: "m")
            .replacingOccurrences(of: "vv", with: "w")
            .map { character -> Character in
                switch character {
                case "0": "o"
                case "1": "l"
                case "3": "e"
                case "5": "s"
                case "$": "s"
                default: character
                }
            }
        let normalizedName = String(normalized)
        if normalizedName != siteName, brands.contains(normalizedName) {
            return .lookalike(brand: normalizedName)
        }
        return nil
    }

    private static func isIPAddress(_ host: String) -> Bool {
        if host.hasPrefix("[") || host.contains(":") { return true }
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    /// The host as written in the code's text, before any encoding.
    private static func rawHost(of text: String) -> String? {
        guard let schemeEnd = text.range(of: "://") else { return nil }
        let rest = text[schemeEnd.upperBound...]
        let authority = rest.prefix { !"/?#".contains($0) }
        let hostPart = authority.split(separator: "@").last.map(String.init) ?? String(authority)
        return hostPart.split(separator: ":").first.map(String.init)
    }

    /// Latin letters mixed with Cyrillic or Greek ones in one label.
    private static func hasMixedScripts(_ host: String) -> Bool {
        for label in host.split(separator: ".") {
            var latin = false, cyrillic = false, greek = false
            for scalar in label.unicodeScalars {
                switch scalar.value {
                case 0x41...0x5A, 0x61...0x7A: latin = true
                case 0x0400...0x04FF: cyrillic = true
                case 0x0370...0x03FF: greek = true
                default: break
                }
            }
            if [latin, cyrillic, greek].filter({ $0 }).count > 1 { return true }
        }
        return false
    }

    // MARK: Punycode (RFC 3492)

    /// "xn--pypal-4ve" → "pаypal"; any other label is returned as it is.
    static func decodeLabel(_ label: String) -> String {
        guard label.lowercased().hasPrefix("xn--") else { return label }
        return decodePunycode(String(label.dropFirst(4))) ?? label
    }

    private static func decodePunycode(_ input: String) -> String? {
        // A DNS label is at most 63 ASCII bytes, including the xn-- prefix. Invalid input is shown as-is.
        guard input.utf8.count <= 59 else { return nil }
        let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
        var n = 128, i = 0, bias = 72
        var output: [UnicodeScalar] = []
        var basicPart = Substring(input)
        var codePart = Substring(input)
        if let delimiter = input.lastIndex(of: "-") {
            basicPart = input[..<delimiter]
            codePart = input[input.index(after: delimiter)...]
        } else {
            basicPart = ""
        }
        for scalar in basicPart.unicodeScalars {
            guard scalar.isASCII else { return nil }
            output.append(scalar)
        }
        var digits = codePart.unicodeScalars.makeIterator()
        func adapt(_ delta: Int, _ numPoints: Int, _ first: Bool) -> Int {
            var delta = first ? delta / damp : delta / 2
            delta += delta / numPoints
            var k = 0
            while delta > ((base - tMin) * tMax) / 2 {
                delta /= base - tMin
                k += base
            }
            return k + (base - tMin + 1) * delta / (delta + skew)
        }
        while let firstScalar = digits.next() {
            let oldI = i
            var w = 1
            var k = base
            var scalar: UnicodeScalar? = firstScalar
            while true {
                guard let current = scalar else { return nil }
                let digit: Int
                switch current.value {
                case 48...57: digit = Int(current.value) - 22
                case 65...90: digit = Int(current.value) - 65
                case 97...122: digit = Int(current.value) - 97
                default: return nil
                }
                let (weightedDigit, multiplyOverflow) = digit.multipliedReportingOverflow(by: w)
                let (nextI, addOverflow) = i.addingReportingOverflow(weightedDigit)
                guard !multiplyOverflow, !addOverflow else { return nil }
                i = nextI
                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if digit < t { break }
                let (nextWeight, weightOverflow) = w.multipliedReportingOverflow(by: base - t)
                guard !weightOverflow else { return nil }
                w = nextWeight
                k += base
                scalar = digits.next()
            }
            // Reject impossible scalars before adapt() as well, keeping all of its arithmetic bounded.
            let increment = i / (output.count + 1)
            guard increment <= 0x10FFFF - n else { return nil }
            bias = adapt(i - oldI, output.count + 1, oldI == 0)
            n += increment
            i %= output.count + 1
            guard let decoded = UnicodeScalar(n) else { return nil }
            output.insert(decoded, at: i)
            i += 1
        }
        var result = ""
        result.unicodeScalars.append(contentsOf: output)
        return result
    }
}
