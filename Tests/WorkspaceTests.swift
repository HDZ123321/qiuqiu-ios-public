import XCTest
import Foundation
@testable import HermesCore
@testable import HermesTransport

final class WorkspaceTests: XCTestCase {
    func testRecentPreviewAndChineseDate() throws {
        XCTAssertEqual(RecentPreview.text("## **完成** [文件](https://example.invalid) `ok`"), "完成 文件 ok")
        XCTAssertFalse(RecentPreview.text("```swift\nlet x = 1\n```").contains("```"))
        XCTAssertTrue(RecentPreview.date(Date(timeIntervalSince1970: 0)).contains("月"))
    }
    func testFilePathValidation() throws {
        XCTAssertNoThrow(try WorkspacePath.validate("资料/fixture.txt"))
        for p in ["../x.txt", "/etc/passwd", ".env", "a/../x.txt", "a\\b.txt", "%2e%2e/x.txt"] {
            XCTAssertThrowsError(try WorkspacePath.validate(p))
        }
    }
    func testProductionURLSessionWorkspaceRoundtrip() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let base=env["QIU_FILE_BASE"], let key=env["QIU_FILE_KEY"], !key.isEmpty else {
            throw XCTSkip("Scoped live workspace credentials absent")
        }
        var settings=ConnectionSettings(); settings.serverURL=base; settings.bearer=key
        let api=HermesAPI()
        let path="acceptance-"+UUID().uuidString+".txt"
        let fixture=Data("Generated nonsecret macOS URLSession fixture".utf8)
        let listing=try await api.workspaceList(settings,path:"")
        XCTAssertTrue(listing.scope.hasSuffix("qiuqiu-workspace"))
        try await api.workspaceWrite(settings,path:path,data:fixture,etag:nil)
        let first=try await api.workspaceRead(settings,path:path)
        XCTAssertEqual(first.data,fixture)
        let edited=Data("Explicit-save fixture edited on macOS".utf8)
        try await api.workspaceWrite(settings,path:path,data:edited,etag:first.etag)
        let after=try await api.workspaceRead(settings,path:path)
        XCTAssertEqual(after.data,edited)
        do {
            try await api.workspaceWrite(settings,path:path,data:fixture,etag:first.etag)
            XCTFail("Stale edit must be rejected")
        } catch let e as HTTPFailure { XCTAssertEqual(e.status,412) }
        print("LIVE_WORKSPACE_ROUNDTRIP_OK generated fixture only; upload/download/edit/conflict verified")
    }
}
