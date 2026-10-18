#if os(iOS)
import SwiftUI
import UIKit

func replyInline(_ text: String) -> Text {
    Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
}

struct MessageCodeView: View {
    let block: MessageBlock
    @State private var wrap = false
    @State private var expanded = false
    @State private var copied = false
    private var long: Bool { block.text.components(separatedBy: "\n").count > 40 }
    private var visible: String { long && !expanded ? block.text.components(separatedBy: "\n").prefix(20).joined(separator: "\n") : block.text }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(block.language?.isEmpty == false ? block.language! : "代码").font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack { controls }
                VStack(alignment: .leading) { controls }
            }
            if wrap {
                Text(visible).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    Text(visible).font(.system(.body, design: .monospaced)).fixedSize(horizontal: true, vertical: false).textSelection(.enabled)
                }
            }
            if long { Button(expanded ? "收起代码" : "展开全部代码") { expanded.toggle() }.frame(minHeight: 44) }
        }.padding(12).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    @ViewBuilder private var controls: some View {
        Button(copied ? "已复制代码" : "复制代码") { UIPasteboard.general.string = block.text; copied = true }.accessibilityIdentifier("reply-code-copy").frame(minHeight: 44)
        Button(wrap ? "横向滚动" : "自动换行") { wrap.toggle() }.accessibilityIdentifier("reply-code-wrap").frame(minHeight: 44)
    }
}

struct MessageTableView: View {
    let block: MessageBlock
    @State private var copied = false
    private func alignment(_ column: Int) -> Alignment {
        guard column < block.alignments.count else { return .leading }
        switch block.alignments[column] { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(block.rows.enumerated()), id: \.offset) { row in
                GridRow {
                    ForEach(Array(row.element.enumerated()), id: \.offset) { cell in
                        replyInline(cell.element).fontWeight(row.offset == 0 ? .semibold : .regular)
                            .padding(10).frame(minWidth: 68, maxWidth: .infinity, alignment: alignment(cell.offset))
                            .background(row.offset == 0 ? Color.secondary.opacity(0.14) : Color.clear)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1) }
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(copied ? "已复制表格" : "复制表格") { UIPasteboard.general.string = block.text; copied = true }.font(.caption).frame(minHeight: 44)
            ScrollView(.horizontal) { grid.fixedSize(horizontal: true, vertical: false) }
                .accessibilityIdentifier("reply-table-horizontal")
        }.background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("reply-table")
    }
}

struct MessagePresentationBlock: View {
    let block: MessageBlock
    @ScaledMetric(relativeTo: .body) private var listIndent = 14
    var body: some View {
        switch block.kind {
        case .code: MessageCodeView(block: block)
        case .table: MessageTableView(block: block)
        case .heading:
            replyInline(block.text).font(block.level == 1 ? .title2 : block.level == 2 ? .title3 : .headline).fontWeight(.semibold).accessibilityAddTraits(.isHeader).textSelection(.enabled)
        case .listItem:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let checked = block.checked {
                    Image(systemName: checked ? "checkmark.square" : "square").accessibilityLabel(checked ? "已完成" : "未完成")
                } else {
                    Text(["-", "+", "*"].contains(block.marker) ? "•" : block.marker).monospacedDigit()
                }
                replyInline(block.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }.padding(.leading, CGFloat(min(block.level, 6)) * listIndent)
        case .quote:
            replyInline(block.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14).padding(.vertical, 6)
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.6)).frame(width: 3) }
                .accessibilityIdentifier("reply-quote")
        case .prose: SelectableReplyText(text: block.text).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#endif
