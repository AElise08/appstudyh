import SwiftUI
import AppKit

struct SlidesNodeView: View {
    @Binding var node: CanvasNode
    @State private var showingBack = false

    private var pages: [String] {
        node.slidesPages ?? []
    }

    private var pageIndex: Int {
        min(max(0, node.slidesPageIndex ?? 0), max(0, pages.count - 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    go(to: pageIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(pageIndex == 0)
                .accessibilityLabel("Slide anterior")

                Text("Slide \(pageIndex + 1) de \(max(1, pages.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    go(to: pageIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(pageIndex >= pages.count - 1)
                .accessibilityLabel("Próximo slide")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            SelectableSlideText(
                text: pages.isEmpty ? "Nenhum texto extraído deste arquivo." : pages[pageIndex],
                selectedText: Binding(
                    get: { node.slidesSelectedText ?? "" },
                    set: { node.slidesSelectedText = $0 }
                ),
                navigationQuote: $node.slidesNavigationQuote
            )
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func go(to index: Int) {
        guard !pages.isEmpty else { return }
        node.slidesPageIndex = min(max(0, index), pages.count - 1)
    }
}

private struct SelectableSlideText: NSViewRepresentable {
    let text: String
    @Binding var selectedText: String
    @Binding var navigationQuote: String?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 18, height: 18)
        view.font = .systemFont(ofSize: 17, weight: .medium)
        view.delegate = context.coordinator
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != text { view.string = text }
        let quote = navigationQuote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !quote.isEmpty, let range = view.string.range(of: quote, options: [.caseInsensitive, .diacriticInsensitive]) {
            let nsRange = NSRange(range, in: view.string)
            view.setSelectedRange(nsRange)
            view.scrollRangeToVisible(nsRange)
            DispatchQueue.main.async { navigationQuote = nil }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectableSlideText

        init(parent: SelectableSlideText) {
            self.parent = parent
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            let range = view.selectedRange()
            parent.selectedText = range.length > 0 ? (view.string as NSString).substring(with: range) : ""
        }
    }
}
