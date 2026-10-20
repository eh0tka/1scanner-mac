import Foundation

/// How a code's content is named and summed up on cards and in the history.
extension CodeContent {
    var kindTitle: String {
        switch self {
        case .link: String(localized: "Link")
        case .wifi: String(localized: "Wi-Fi")
        case .contact: String(localized: "Contact")
        case .event: String(localized: "Event")
        case .phone: String(localized: "Phone")
        case .sms: String(localized: "Message")
        case .email: String(localized: "Email")
        case .location: String(localized: "Location")
        case .product(_, let kind): kind == .isbn ? String(localized: "Book") : String(localized: "Product")
        case .text: String(localized: "Text")
        }
    }

    var systemImage: String {
        switch self {
        case .link: "link"
        case .wifi: "wifi"
        case .contact: "person.crop.circle"
        case .event: "calendar"
        case .phone: "phone"
        case .sms: "message"
        case .email: "envelope"
        case .location: "mappin.and.ellipse"
        case .product(_, let kind): kind == .isbn ? "book" : "barcode"
        case .text: "text.alignleft"
        }
    }

    /// One line: the real site of a link, the network name, the contact's name…
    var summary: String {
        switch self {
        case .link(let url): LinkCheck(url: url).host
        case .wifi(let wifi): wifi.ssid
        case .contact(let contact): contact.name ?? contact.phones.first ?? contact.emails.first ?? ""
        case .event(let event): event.title ?? ""
        case .phone(let number): number
        case .sms(let number, _): number
        case .email(let address, _, _): address
        case .location(let latitude, let longitude, let query):
            query ?? String(format: "%.5f, %.5f", latitude, longitude)
        case .product(let number, let kind): "\(kind.displayName) \(number)"
        case .text(let text): text.replacingOccurrences(of: "\n", with: " ")
        }
    }

    var hasWarnings: Bool {
        if case .link(let url) = self { return !LinkCheck(url: url).warnings.isEmpty }
        return false
    }
}
