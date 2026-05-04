/// A type that can be displayed and searched in a PickerPanel.
public protocol Pickable {
    /// Text shown in the picker's default cell.
    var displayText: String { get }
    /// Text used for filtering. Defaults to `displayText`.
    var searchText: String { get }
}

extension Pickable {
    public var searchText: String { displayText }
}

extension String: Pickable {
    public var displayText: String { self }
}
