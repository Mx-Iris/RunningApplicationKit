import AppKit

// Deprecated spellings kept so that callers written against the previous release keep
// compiling. They are collected here rather than spread through the types they alias so
// that removing them in the next minor is a matter of deleting one file -- plus the
// `allowsColumns` property and the extra initializer overload on each configuration,
// which have to live beside what they forward to.

extension RunningPickerTabViewController {
    /// Superseded by ``ApplicationField``: a field is not necessarily rendered as a column.
    @available(*, deprecated, renamed: "ApplicationField")
    public typealias ApplicationColumn = ApplicationField

    /// Superseded by ``ProcessField``: a field is not necessarily rendered as a column.
    @available(*, deprecated, renamed: "ProcessField")
    public typealias ProcessColumn = ProcessField
}
