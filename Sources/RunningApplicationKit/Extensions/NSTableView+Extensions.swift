import AppKit

extension NSTableView {
    func makeView<View: NSView>(ofClass viewClass: View.Type, modify: ((View) -> Void)? = nil) -> View {
        if let cellView = makeView(withIdentifier: .init(String(describing: viewClass)), owner: nil) as? View {
            modify?(cellView)
            return cellView
        } else {
            let cellView = View()
            cellView.identifier = .init(String(describing: viewClass))
            modify?(cellView)
            return cellView
        }
    }
}
