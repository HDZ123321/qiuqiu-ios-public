import XCTest
import UniformTypeIdentifiers
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
    func testUnsupportedAndExcessProvidersDoNotPartiallySucceed() async {
        do { _ = try await ShareProviderIntake.load([NSItemProvider()]); XCTFail("unsupported must reject entire batch") } catch {}
        let providers = (0..<5).map { NSItemProvider(object: "fixture \($0)" as NSString) }
        do { _ = try await ShareProviderIntake.load(providers); XCTFail("excess providers must reject entire batch") } catch {}
    }
}
