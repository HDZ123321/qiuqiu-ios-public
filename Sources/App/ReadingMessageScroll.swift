#if os(iOS)
import SwiftUI

private struct ReadingBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Geometry updates from growing text do not opt the reader out of following;
/// only a reader gesture does. Content below a paused reader never forces a jump.
struct ReadingMessageScroll<Content: View>: View {
    let revision: String
    let conversationID: UUID?
    var jumpTarget: UUID? = nil
    @ViewBuilder let content: () -> Content
    @State private var position = MessageReadPosition()
    @State private var bottom: CGFloat = 0
    @State private var dragging = false
    @State private var viewport: CGFloat = 0
    var body: some View {
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        content()
                        Color.clear.frame(height: 1).id("reading-bottom")
                            .background(GeometryReader { p in Color.clear.preference(key: ReadingBottomKey.self, value: p.frame(in: .named("reading-viewport")).maxY) })
                    }
                }.coordinateSpace(name: "reading-viewport")
                .accessibilityIdentifier("message-reading-scroll")
                .onAppear { viewport = geometry.size.height }
                .onChange(of: geometry.size.height) { viewport = $0 }
                .onPreferenceChange(ReadingBottomKey.self) { value in
                    bottom = value
                    if dragging { position.userScrolled(distanceFromBottom: Double(value - viewport)) }
                }
                .simultaneousGesture(DragGesture().onChanged { value in
                    dragging = true
                    if value.translation.height > 8 { position.userScrolled(distanceFromBottom: 1000) }
                }.onEnded { _ in
                    position.userScrolled(distanceFromBottom: Double(bottom - viewport)); dragging = false
                })
                .onChange(of: revision) { _ in
                    position.contentChanged()
                    if position.following { proxy.scrollTo("reading-bottom", anchor: .bottom) }
                }
                .onChange(of: conversationID) { _ in position.follow() }
                .onChange(of: jumpTarget) { target in
                    guard let target else { return }
                    position.userScrolled(distanceFromBottom: 1000)
                    proxy.scrollTo(target, anchor: .top)
                }
                .overlay(alignment: .bottomTrailing) {
                    if position.hasNewContent {
                        Button { position.follow(); proxy.scrollTo("reading-bottom", anchor: .bottom) } label: {
                            Label("有新内容 · 回到底部", systemImage: "arrow.down")
                                .font(.subheadline).padding(10).background(.regularMaterial, in: Capsule())
                        }.padding(8).accessibilityIdentifier("message-new-content")
                    }
                }
            }
        }
    }
}

#endif
