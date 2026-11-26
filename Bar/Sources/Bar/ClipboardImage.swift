import AppKit

/// The image on the clipboard, when an image is what was copied.
///
/// Plenty of apps (Word, Excel, Notes) put a picture of copied *text* on the
/// clipboard too, so real text wins. The exception is a lone web address,
/// which some browsers add beside "Copy Image".
enum ClipboardImage {
    static func data(from pasteboard: NSPasteboard) -> Data? {
        let text = (pasteboard.string(forType: .string) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty || isLoneWebAddress(text) else { return nil }
        let types: [NSPasteboard.PasteboardType] = [.png, .init("public.jpeg"), .tiff]
        return types.lazy.compactMap { pasteboard.data(forType: $0) }.first
    }

    private static func isLoneWebAddress(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace),
              let scheme = URL(string: text)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
