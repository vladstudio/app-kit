import AppKit

/// Generic floating picker panel with search field and table view.
/// Subclass or use the `onPick` callback to handle selection.
open class PickerPanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    public let search = NSTextField()
    public let table = NSTableView()
    public private(set) var filtered: [String] = []
    private var all: [String] = []
    private var prevApp: NSRunningApplication?
    private var filterFn: ((String, String) -> Bool)?
    private var pickHandler: ((Int, String) -> Void)?

    public init(title panelTitle: String, placeholder: String) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
                   styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
                   backing: .buffered, defer: false)
        title = panelTitle
        titlebarAppearsTransparent = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .none

        let cv = contentView!

        search.placeholderString = placeholder
        search.isBordered = false
        search.focusRingType = .none
        search.drawsBackground = false
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(search)

        let sep = NSBox(); sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(sep)

        let col = NSTableColumn(identifier: .init("c"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 28
        table.style = .plain
        table.doubleAction = #selector(pick)
        table.target = self

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(scroll)

        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: cv.topAnchor, constant: 28),
            search.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -12),
            sep.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 6),
            sep.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: sep.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
        ])
    }

    @available(*, unavailable) required public init?(coder: NSCoder) { fatalError() }

    // MARK: - Configuration

    /// Set a custom filter function. Default is case-insensitive contains.
    public func setFilter(_ fn: @escaping (String, String) -> Bool) {
        filterFn = fn
    }

    /// Set the selection handler. Called with (row index, item string).
    public func onPick(_ handler: @escaping (Int, String) -> Void) {
        pickHandler = handler
    }

    // MARK: - Show / Dismiss

    public func show(items: [String]) {
        all = items
        prevApp = NSWorkspace.shared.frontmostApplication
        search.stringValue = ""
        refilter()
        center()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(search)
        NSApp.activate()
    }

    public func dismiss() {
        orderOut(nil)
        prevApp?.activate()
    }

    // MARK: - Filtering

    private func refilter() {
        let q = search.stringValue
        if q.isEmpty {
            filtered = all
        } else {
            let match = filterFn ?? { item, query in item.localizedCaseInsensitiveContains(query) }
            filtered = all.filter { match($0, q) }
        }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    @objc private func pick() {
        let row = table.selectedRow
        guard row >= 0, row < filtered.count else { return }
        let item = filtered[row]
        dismiss()
        pickHandler?(row, item)
    }

    // MARK: - NSTextFieldDelegate

    public func controlTextDidChange(_ n: Notification) { refilter() }

    public func control(_ control: NSControl, textView: NSTextView,
                        doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(insertNewline(_:)): pick(); return true
        case #selector(cancelOperation(_:)): dismiss(); return true
        case #selector(moveUp(_:)):
            moveSel(max(0, table.selectedRow - 1)); return true
        case #selector(moveDown(_:)):
            moveSel(min(filtered.count - 1, table.selectedRow + 1)); return true
        default: return false
        }
    }

    private func moveSel(_ row: Int) {
        guard row >= 0 else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    // MARK: - NSTableViewDataSource & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    private static let cellID = NSUserInterfaceItemIdentifier("item")

    /// Override this to customize cell rendering.
    open func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let text = filtered[row]

        if let cell = tv.makeView(withIdentifier: Self.cellID, owner: nil) as? NSTableCellView {
            cell.textField?.stringValue = text
            return cell
        }

        let cell = NSTableCellView()
        cell.identifier = Self.cellID

        let tf = NSTextField(labelWithString: text)
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(tf)
        cell.textField = tf

        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
