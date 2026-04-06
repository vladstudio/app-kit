import AppKit

/// Saves and restores the full pasteboard state (all types, not just strings).
public struct ClipboardSnapshot: Sendable {
    private let items: [[(NSPasteboard.PasteboardType, Data)]]

    public static func save() -> ClipboardSnapshot {
        let pb = NSPasteboard.general
        let items = pb.pasteboardItems?.map { item in
            item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            }
        } ?? []
        return ClipboardSnapshot(items: items)
    }

    public func restore() {
        guard !items.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        for itemData in items {
            let item = NSPasteboardItem()
            for (type, data) in itemData { item.setData(data, forType: type) }
            pb.writeObjects([item])
        }
    }
}
