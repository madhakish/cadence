import Foundation

/// CSV field encoding shared with web `core.js` `csvField`: the sets export is
/// opened in spreadsheets, so a free-text field (a note, an exercise name, a
/// value that arrived in an imported backup) must never be evaluated as a
/// formula. A field starting with = + - @, tab or CR gets a leading
/// apostrophe; any field containing a comma, quote, LF or CR is quoted.
public enum CSVExport {
    static let formulaTriggers: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

    public static func field(_ value: String) -> String {
        var text = value
        if let first = text.first, formulaTriggers.contains(first) { text = "'" + text }
        if text.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return text
    }
}
