import XCTest
import UniformTypeIdentifiers
import UIKit
@testable import QiuQiu

final class ShareProviderTests: XCTestCase {
    func testOfficialTextAndURLProvidersAreDataNotNetworkRequests() async throws {
        let text = NSItemProvider(object: "Untrusted fixture text" as NSString)
        let url = NSItemProvider(object: URL(string: "https://example.org/fixture")! as NSURL)
        print("SHARE_PROVIDER_TYPES", text.registeredTypeIdentifiers, url.registeredTypeIdentifiers)
        let result = try await ShareProviderIntake.load([text, url])
        XCTAssertTrue(result.text.contains("Untrusted fixture text"))
        XCTAssertTrue(result.text.contains("https://example.org/fixture"))
        XCTAssertTrue(result.files.isEmpty)
    }
    func testOfficialDocumentFileProviderPreservesBytesAndName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("shared.txt")
        try Data("bounded document fixture".utf8).write(to: url)
        let provider = NSItemProvider(contentsOf: url)!
        let result = try await ShareProviderIntake.load([provider])
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.files.first?.data, Data("bounded document fixture".utf8))
        XCTAssertEqual(result.files.first?.name, "shared.txt")
    }
    func testOfficialImageProviderUsesPixelBoundedNormalizer() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 240), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(image.pngData(), nil); return nil
        }
        let result = try await ShareProviderIntake.load([provider])
        XCTAssertEqual(result.files.count, 1)
        XCTAssertEqual(result.files.first?.mime, "image/jpeg")
        XCTAssertLessThanOrEqual(result.files.first?.data.count ?? Int.max, AttachmentFailure.limit)
    }
    func testUnsupportedAndExcessProvidersDoNotPartiallySucceed() async {
        do { _ = try await ShareProviderIntake.load([NSItemProvider()]); XCTFail("unsupported must reject entire batch") } catch {}
        let providers = (0..<5).map { NSItemProvider(object: "fixture \($0)" as NSString) }
        do { _ = try await ShareProviderIntake.load(providers); XCTFail("excess providers must reject entire batch") } catch {}
    }
}
