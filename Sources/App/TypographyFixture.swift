#if DEBUG && targetEnvironment(simulator)
import Foundation

enum TypographyFixture {
    static var text: String {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-selection") { return "前缀 TARGET 后缀" }
        if args.contains("--ui-typography-code") {
            return "# Code reading\n```swift\n  let original = \"" + String(repeating: "long line ", count: 16) + "\"\n\n" + (1...55).map { "  let value\($0) = \($0)" }.joined(separator: "\n") + "\n```\n\nAfter code remains visible."
        }
        if args.contains("--ui-typography-table") {
            return "# Tables and quotes\n> **Balanced quote** with [safe link](https://example.org).\n>\n> Second paragraph stays inside the rule.\n\n| A | B |\n| :--- | ---: |\n| **One** | Two |\n\n| Wide first column | Second column | Third column | Fourth column |\n| :--- | :---: | ---: | --- |\n| escaped \\| pipe | `a|b` | 123.45 | End of wide table |\n\nAfter table stays in viewport."
        }
        if args.contains("--ui-typography-stream") {
            return "# Reading anchor\n" + String(repeating: "Reader paragraph stays in place while new content arrives below.\n\n", count: 28) + "```swift\n  let partial = 1\n"
        }
        return "# 一级标题 Heading\n中文与 Latin 正文使用一致字号与段落间距，长段落应自然换行，不改变复制原文。\n\n## 二级标题\n1. Ordered item with a deliberately longer continuation that wraps with a hanging indent on narrow screens.\n   continuation stays with item\n  - Nested bullet **emphasis**\n    1. Deeper ordered item\n- [x] Completed task, read only\n- [ ] Pending task, read only\n### 三级标题\n###### 深层标题 capped hierarchy\n> Inline **bold**, `code` and [safe link](https://example.org).\n\nFinal paragraph remains visible."
    }
}
#endif
