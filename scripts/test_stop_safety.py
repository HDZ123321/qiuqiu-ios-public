"""Regression: sending must not replace its hit target with immediate server stop."""
import pathlib
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class StopSafety(unittest.TestCase):
    def test_stop_requires_separate_confirmation(self):
        source = (ROOT/'Sources/App/QiuQiuApp.swift').read_text()
        self.assertNotIn('Button("停止", role: .destructive) { store.cancel() }', source)
        self.assertIn('.confirmationDialog(', source)
        self.assertIn('store.cancel()', source)
    def test_detach_never_calls_stop(self):
        source = (ROOT/'Sources/App/ChatStore.swift').read_text()
        detach = source.split('func detach() {',1)[1].split('private func reconcile',1)[0]
        self.assertNotIn('/stop', detach)
        self.assertNotIn('cancel()', detach.replace('generation?.cancel()', '').replace('eventTask?.cancel()', ''))
if __name__ == '__main__': unittest.main()
