import XCTest
@testable import HermesCore

final class CronTests: XCTestCase {
    func testReadOnlyJobsCannotBuildMutationPayload() throws {
        let data=Data(#"{"id":"aabbccddeeff","name":"Existing","enabled":true,"manageable":false,"revision":"rev"}"#.utf8)
        let job=try JSONDecoder().decode(CronJob.self,from:data)
        XCTAssertThrowsError(try CronCommand(action:.delete,job:job).payload())
    }
    func testCreateIsExplicitAndCannotEnableOnCreation() throws {
        let command=CronCommand(action:.create,name:"Daily",prompt:"Summarize",schedule:"0 9 * * *")
        let payload=try JSONSerialization.jsonObject(with: command.payload()) as! [String:String]
        XCTAssertEqual(payload["confirm"],"create")
        XCTAssertNil(payload["enabled"])
        XCTAssertEqual(command.path,"cron")
        XCTAssertThrowsError(try CronCommand(action:.create,name:"",prompt:"x",schedule:"every 1h").payload())
    }
    func testEditRequiresPauseAndExactRevision() throws {
        var job=try JSONDecoder().decode(CronJob.self,from:Data(#"{"id":"aabbccddeeff","name":"App","enabled":true,"manageable":true,"revision":"abc","prompt":"Old"}"#.utf8))
        XCTAssertThrowsError(try CronCommand(action:.edit,job:job,name:"New",prompt:"New",schedule:"every 1h").payload())
        job.enabled=false
        let command=CronCommand(action:.edit,job:job,name:"New",prompt:"New",schedule:"every 1h")
        let payload=try JSONSerialization.jsonObject(with:command.payload()) as! [String:String]
        XCTAssertEqual(payload["revision"],"abc")
        XCTAssertEqual(command.path,"cron/aabbccddeeff/edit")
    }
    func testInvalidIdentifierNeverBecomesRoute() throws {
        let job=try JSONDecoder().decode(CronJob.self,from:Data(#"{"id":"../admin","name":"Bad","enabled":false,"manageable":true,"revision":"abc"}"#.utf8))
        XCTAssertThrowsError(try CronCommand(action:.run,job:job).payload())
    }
    func testLatestExecutionSnapshotIsMetadataOnly() throws {
        let data=Data(#"{"id":"aabbccddeeff","name":"App","enabled":true,"manageable":true,"revision":"abc","latest_execution":{"id":"e1","status":"completed","claimed_at":"2026-10-18T00:00:00+08:00","started_at":null,"finished_at":"2026-10-18T00:05:00+08:00","source":"scheduler","error":"internal native text with /paths","pid":1234}}"#.utf8)
        let job=try JSONDecoder().decode(CronJob.self,from:data)
        let snapshot=try XCTUnwrap(job.latest_execution)
        XCTAssertEqual(snapshot.status,"completed")
        // Decoding struct has no error/pid fields: raw payload keys cannot leak.
        let encoded=String(decoding:try JSONEncoder().encode(snapshot),as:UTF8.self)
        XCTAssertFalse(encoded.contains("paths"))
        XCTAssertFalse(encoded.contains("pid"))
    }
}
