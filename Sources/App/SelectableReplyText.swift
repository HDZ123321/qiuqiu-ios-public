#if os(iOS)
import SwiftUI
import UIKit

/// Native read-only range selection on iOS versions where SwiftUI Text exposes
/// only whole-block Copy. Block structure/source copy stay with the renderer.
struct SelectableReplyText: UIViewRepresentable {
    let text: String
    var style: UIFont.TextStyle = .body
    var semibold = false
    var monospaced = false
    var markdown = true
    var naturalWidth = false
    @Environment(\.openURL) private var openURL
    @Environment(\.sizeCategory) private var sizeCategory
    func makeCoordinator() -> Coordinator { Coordinator(openURL) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false; view.isSelectable = true; view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero; view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = true
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        view.accessibilityIdentifier = monospaced || naturalWidth ? "quote-gesture-excluded" : nil
        context.coordinator.openURL = openURL
        let attributed = Self.attributed(text, style: style, semibold: semibold, monospaced: monospaced, markdown: markdown)
        // Timer/stream updates must not reset an unchanged native selection.
        if view.attributedText != attributed {
            let selection = view.selectedRange
            view.attributedText = attributed
            if NSMaxRange(selection) <= attributed.length { view.selectedRange = selection }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = naturalWidth ? max(1, ceil(uiView.attributedText.size().width)) : max(1, proposal.width ?? 300)
        return CGSize(width: width, height: ceil(uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }
    static func attributed(_ text: String, style: UIFont.TextStyle = .body, semibold: Bool = false, monospaced: Bool = false, markdown: Bool = true) -> NSAttributedString {
        let base = UIFont.preferredFont(forTextStyle: style)
        let initial = markdown ? ((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)) : AttributedString(text)
        let result = NSMutableAttributedString(attributedString: NSAttributedString(initial))
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 4
        result.addAttributes([.font: base, .foregroundColor: UIColor.label, .paragraphStyle: paragraph], range: NSRange(location: 0, length: result.length))
        // Foundation Markdown intents are semantic, not UIKit fonts. Convert them
        // explicitly so native selection retains bold/emphasis/inline code.
        var offset = 0
        for run in initial.runs {
            let count = String(initial[run.range].characters).utf16.count
            let intent = run.inlinePresentationIntent ?? []
            let mono = monospaced || intent.contains(.code)
            var font = mono ? UIFont.monospacedSystemFont(ofSize: base.pointSize, weight: semibold ? .semibold : .regular) : base
            var traits = font.fontDescriptor.symbolicTraits
            if semibold || intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { font = UIFont(descriptor: descriptor, size: base.pointSize) }
            result.addAttribute(.font, value: font, range: NSRange(location: offset, length: count))
            offset += count
        }
        return result
    }
    final class Coordinator: NSObject, UITextViewDelegate {
        var openURL: OpenURLAction
        init(_ action: OpenURLAction) { openURL = action }
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            openURL(URL); return false // retain MarkdownMessage confirmation boundary
        }
    }
}
#endif
