#if os(iOS)
import SwiftUI
import UIKit

/// Observe only intentional leftward pans inside this message. Native selection,
/// controls and nested horizontal scrollers retain ownership of their gestures.
struct MessageQuoteSwipe: UIViewRepresentable {
    let quote: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(quote) }
    func makeUIView(context: Context) -> UIView {
        let view = AnchorView(); view.isUserInteractionEnabled = false
        view.install = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view, let window = view.window else { return }
            coordinator.attach(view, window: window)
        }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { context.coordinator.action = quote }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.detach() }
    final class AnchorView: UIView {
        var install: (() -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); install?() }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void
        weak var anchor: UIView?
        weak var window: UIWindow?
        var pan: UIPanGestureRecognizer?
        init(_ action: @escaping () -> Void) { self.action = action }
        func attach(_ anchor: UIView, window: UIWindow) {
            detach(); self.anchor = anchor; self.window = window
            let pan = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
            pan.delegate = self; pan.cancelsTouchesInView = false
            window.addGestureRecognizer(pan); self.pan = pan
        }
        func detach() { if let pan { window?.removeGestureRecognizer(pan) }; pan = nil }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let anchor, anchor.window != nil, !anchor.isHidden,
                  anchor.bounds.contains(touch.location(in: anchor)) else { return false }
            var node = touch.view
            while let view = node {
                if view is UIControl { return false }
                if let text = view as? UITextView, text.selectedRange.length > 0 || text.accessibilityIdentifier == "quote-gesture-excluded" { return false }
                if let scroll = view as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 4 { return false }
                node = view.superview
            }
            return true
        }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: window)
            return v.x < -80 && abs(v.x) > abs(v.y) * 2
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        @objc func moved(_ pan: UIPanGestureRecognizer) {
            let t = pan.translation(in: window)
            if pan.state == .ended, t.x < -64, abs(t.x) > abs(t.y) * 2 { action() }
        }
    }
}
#endif
