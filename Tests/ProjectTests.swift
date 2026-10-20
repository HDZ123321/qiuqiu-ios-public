import XCTest
@testable import HermesCore

final class ProjectTests: XCTestCase {
    func testLegacyChatDefaultsAndPendingBodyUnchanged() throws {
        let chat = try JSONDecoder().decode(Chat.self, from: Data(#"{"id":"12345678-1234-1234-1234-123456789012","messages":[]}"#.utf8))
        XCTAssertEqual(chat.workspaceProjectID, "default")
        let old = try PendingRun(input:"hello",model:"fixture",sessionID:nil,history:[],replyID:UUID())
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with:old.body) as? [String:Any])
        XCTAssertNil(payload["project_id"])
        XCTAssertEqual(payload["artifact_delivery"] as? String,"workspace-file-v2")
    }
    func testProjectBindingIsLocalAndBlockedByPendingRun() throws {
        var chat=Chat(); let project=WorkspaceProject(id:"p_"+String(repeating:"a",count:32),name:"研究 A")
        try chat.bindWorkspace(project)
        XCTAssertEqual(chat.workspaceProjectID,project.id)
        chat.run=try PendingRun(input:"hello",model:"fixture",sessionID:nil,history:[],replyID:UUID(),project:project)
        let snapshot=try XCTUnwrap(chat.run)
        let payload=try XCTUnwrap(JSONSerialization.jsonObject(with:snapshot.body) as? [String:Any])
        XCTAssertEqual(payload["project_id"] as? String,project.id)
        XCTAssertEqual(payload["artifact_delivery"] as? String,"workspace-project-v1")
        XCTAssertThrowsError(try chat.bindWorkspace(.defaultProject))
        XCTAssertEqual(chat.run?.body,snapshot.body)
        XCTAssertEqual(chat.run?.key,snapshot.key)
        let decoded=try JSONDecoder().decode(Chat.self,from:JSONEncoder().encode(chat))
        XCTAssertEqual(decoded.workspaceProjectID,project.id)
        chat.run?.status="completed";try chat.bindWorkspace(.defaultProject)
        XCTAssertEqual(chat.workspaceProjectID,"default")
        XCTAssertEqual(chat.run?.body,snapshot.body)
    }
    func testOpaqueProjectValidation() throws {
        for id in ["../other","/home","p_abc","p_"+String(repeating:"A",count:32),".hidden"] {
            XCTAssertThrowsError(try WorkspaceProject(id:id,name:"bad").validate())
        }
        try WorkspaceProject.defaultProject.validate()
        try WorkspaceProject(id:"p_"+String(repeating:"b",count:32),name:"研究").validate()
    }
}
