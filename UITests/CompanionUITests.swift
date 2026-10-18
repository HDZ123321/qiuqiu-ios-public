import XCTest

final class CompanionUITests: XCTestCase {
    func testTypographyHeadingsListsLightAndDarkHugeText() {
        for dark in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-replies", "--ui-typography"] + (dark ? ["--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
            app.launch(); app.buttons["跟我说"].tap()
            let title = app.staticTexts["一级标题 Heading"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            screenshot(dark ? "typography-headings-dark-huge" : "typography-headings-light")
            let viewport = app.scrollViews["message-reading-scroll"]
            let task = app.staticTexts["Completed task, read only"]
            for _ in 0..<18 {
                if task.isHittable { break }
                viewport.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(task.isHittable)
            screenshot(dark ? "typography-lists-dark-huge" : "typography-lists-light")
            XCTAssertTrue(app.buttons["完成"].isHittable)
            app.terminate()
        }
    }
    func testTypographyCodeWrapExpandCopyAndTableContainment() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-replies", "--ui-typography", "--ui-typography-code"]
        app.launch(); app.buttons["跟我说"].tap()
        let copy = app.buttons["reply-code-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
        XCTAssertTrue(app.buttons["已复制代码"].exists)
        app.buttons["reply-code-wrap"].tap(); screenshot("typography-code-wrapped")
        app.buttons["reply-code-wrap"].tap(); screenshot("typography-code-horizontal")
        let expand = app.buttons["展开全部代码"]
        for _ in 0..<10 { if expand.isHittable { break }; app.swipeUp(velocity: .slow) }
        XCTAssertTrue(expand.isHittable); expand.tap(); screenshot("typography-code-expanded")
        app.terminate()
        app.launchArguments = ["--ui-replies", "--ui-typography", "--ui-typography-table", "--ui-dark"]
        app.launch(); app.buttons["跟我说"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "复制表格")).firstMatch.waitForExistence(timeout: 5))
        screenshot("typography-table-short-wide-quote-dark")
        let tableCopies = app.buttons.matching(NSPredicate(format: "label == %@", "复制表格"))
        for _ in 0..<4 { if tableCopies.count > 1 && tableCopies.element(boundBy: 1).isHittable { break }; app.swipeUp(velocity: .slow) }
        XCTAssertEqual(tableCopies.count, 2)
        tableCopies.element(boundBy: 1).tap(); XCTAssertTrue(app.buttons["已复制表格"].exists)
        screenshot("typography-wide-table-copy")
        // SwiftUI propagates the parent table AX identifier to nested scrolls.
        // Drag within the row below the second copy control rather than guessing AX type.
        let rowY = app.buttons["已复制表格"].frame.maxY + 42
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width - 55, dy: rowY))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 60, dy: rowY))
        start.press(forDuration: 0.1, thenDragTo: end)
        start.press(forDuration: 0.1, thenDragTo: end)
        let lastCell = app.staticTexts["End of wide table"]
        XCTAssertTrue(lastCell.isHittable)
        screenshot("typography-wide-table-horizontal-revealed")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 3))
        // Wait for rotation animation, not merely the orientation request.
        Thread.sleep(forTimeInterval: 2)
        screenshot("typography-table-landscape-wide-viewport")
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }
    func testTypographyStreamingReaderStaysPutAndCanFollow() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-replies", "--ui-typography", "--ui-typography-stream"]
        app.launch(); app.buttons["跟我说"].tap()
        // Let the first synthetic chunk follow, then explicitly read older text.
        let viewport = app.scrollViews["message-reading-scroll"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        viewport.swipeDown(); viewport.swipeDown()
        let indicator = app.buttons["message-new-content"]
        XCTAssertTrue(indicator.waitForExistence(timeout: 8)); screenshot("typography-stream-paused-unclosed-fence")
        indicator.tap()
        XCTAssertFalse(indicator.exists); screenshot("typography-stream-follow-tail")
    }

    func testReplyImageFilePreviewShareAndAnswerDraft() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-replies"]; app.launch()
        app.buttons["跟我说"].tap()
        let image = app.buttons["reply-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 15)); image.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reply-image-preview"].waitForExistence(timeout: 5)); screenshot("reply-inline-image-preview")
        app.buttons["关闭预览"].tap()
        let files = app.buttons.matching(identifier: "reply-file-preview")
        for _ in 0..<5 { if files.count > 1 && files.element(boundBy: 1).isHittable { break }; app.swipeUp() }
        XCTAssertEqual(files.count, 2); files.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["Generated downloadable document fixture.\nExact bytes verified."].waitForExistence(timeout: 10)); screenshot("reply-generated-file-preview")
        app.buttons["下载 / 分享产物"].tap()
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Copy")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10)); screenshot("reply-generated-file-share")
        copy.tap(); app.buttons["关闭分享"].tap(); app.buttons["关闭预览"].tap()
        for _ in 0..<5 { if app.buttons["reply-answer"].isHittable { break }; app.swipeDown() }
        let composer = app.textFields.firstMatch
        composer.tap(); composer.typeText("Preserve existing draft")
        app.buttons["reply-answer"].tap()
        app.buttons["取消"].tap()
        XCTAssertEqual(composer.value as? String, "Preserve existing draft")
        app.buttons["reply-answer"].tap()
        XCTAssertTrue(app.textFields["answer-text"].waitForExistence(timeout: 5))
        app.textFields["answer-text"].tap()
        let field = app.textFields["answer-text"]
        field.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap(); field.typeText("My explicit answer") }
        else { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Preserve existing draft".count) + "My explicit answer") }
        screenshot("reply-answer-native-contract-limit")
        app.buttons["answer-draft"].tap()
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "My explicit answer")
        XCTAssertTrue(app.buttons["发送"].isEnabled)
    }
    func testReplyFormattingLargeTextAndApprovalConfirmation() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-replies", "--ui-formatting", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]; app.launch()
        app.buttons["跟我说"].tap()
        let reading = app.scrollViews["message-reading-scroll"]
        for _ in 0..<12 {
            if app.buttons["复制表格"].isHittable { break }
            reading.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(app.buttons["复制表格"].waitForExistence(timeout: 5)); screenshot("reply-table-quote-accessibility-text")
        let copyCode = app.buttons["reply-code-copy"]
        for _ in 0..<16 {
            if copyCode.isHittable { break }
            reading.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(copyCode.isHittable); copyCode.tap(); screenshot("reply-long-code-dynamic-type")
        app.terminate()
        app.launchArguments = ["--ui-replies", "--ui-approval", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]; app.launch()
        app.tabBars.buttons["任务"].tap()
        let once = app.buttons["approval-once"]
        for _ in 0..<8 { if once.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(once.waitForExistence(timeout: 5)); XCTAssertTrue(once.isEnabled); screenshot("reply-approval-exact-request")
        once.tap(); XCTAssertTrue(app.buttons["确认仅批准本次"].waitForExistence(timeout: 5)); screenshot("reply-approval-user-confirmation")
        app.buttons["取消"].tap(); XCTAssertTrue(once.isEnabled)
        once.tap(); app.buttons["确认仅批准本次"].tap()
        XCTAssertTrue(app.staticTexts["当前没有进行中的任务"].waitForExistence(timeout: 15)); screenshot("reply-approval-server-readback-completed")
    }
    private func screenshot(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testAllSourcePaginationLoadsOlderReadOnlyConversation() {
        let app=XCUIApplication(); app.launchArguments=["--ui-sessions","--ui-sessions-paged"]; app.launch()
        app.tabBars.buttons["回看"].tap()
        app.buttons["server-sessions-navigation"].tap()
        app.buttons["获取服务器会话"].tap()
        XCTAssertTrue(app.staticTexts["已加载 50 / 51 条记录"].waitForExistence(timeout:10))
        let more=app.buttons["加载更多会话"]
        for _ in 0..<35 { if more.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(more.isHittable); more.tap()
        let row=app.buttons["server-session-fixture_readonly"]
        for _ in 0..<5 { if row.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout:5)); XCTAssertTrue(row.isHittable)
        screenshot("all-source-older-page-wechat")
        row.tap()
        XCTAssertTrue(app.staticTexts["Read-only WeChat fixture"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["完成"].exists)
        XCTAssertTrue(app.buttons["发送"].exists)
        XCTAssertFalse(app.buttons["发送"].isEnabled) // no draft; opening never sends
        screenshot("all-source-original-wechat-continuation")
    }
    func testServerRowOneTapOpensStoredHistoryWithoutImportOrSend() {
        let app=XCUIApplication(); app.launchArguments=["--ui-sessions"]; app.launch()
        app.tabBars.buttons["回看"].tap()
        app.buttons["server-sessions-navigation"].tap()
        app.buttons["获取服务器会话"].tap()
        let row=app.buttons["server-session-fixture_owned"]
        XCTAssertTrue(row.waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["Garden planning"].exists)
        screenshot("server-session-real-title")
        row.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["Historical garden question"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["Historical garden answer"].exists)
        XCTAssertFalse(app.buttons["读取真实历史文字"].exists)
        XCTAssertFalse(app.buttons["打开本机会话 / 准备继续"].exists)
        XCTAssertFalse(app.buttons["发送"].isEnabled)
        screenshot("server-one-tap-history-open")
    }
    func testOngoingServerSessionShowsHonestSyncStateWithoutSending() {
        // Ongoing-conversation acceptance: opening an owned server session starts
        // bounded foreground sync and shows the real sync state, not a fake "live".
        let app=XCUIApplication(); app.launchArguments=["--ui-sessions","--ui-sync-active"]; app.launch()
        app.tabBars.buttons["回看"].tap()
        app.buttons["server-sessions-navigation"].tap()
        app.buttons["获取服务器会话"].tap()
        let row=app.buttons["server-session-fixture_owned"]
        XCTAssertTrue(row.waitForExistence(timeout:10)); row.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout:10))
        // Server lease held by the original channel -> busy/wait badge, send stays off.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sync-state-busy").firstMatch.waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["发送"].isEnabled)
        screenshot("server-session-ongoing-busy-sync")
    }
    func testVoiceEntryCancelDoesNotSendOrReplaceDraft() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-history"]; app.launch()
        app.buttons["跟我说"].tap()
        let composer = app.textFields.firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap(); composer.typeText("keep draft")
        app.buttons["voice-input"].tap()
        XCTAssertTrue(app.buttons["voice-start"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["voice-insert"].isEnabled)
        screenshot("voice-on-device-disclosure")
        app.buttons["voice-cancel"].tap()
        XCTAssertTrue(app.buttons["voice-input"].waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "keep draft")
    }
    func testRealWorkspaceBrowseEditPreviewAndShare() throws {
        let env=ProcessInfo.processInfo.environment
        guard let base=env["QIU_FILE_BASE"], let key=env["QIU_FILE_KEY"], !key.isEmpty else { throw XCTSkip("Scoped file test credentials absent") }
        let app=XCUIApplication(); app.launchArguments=["--ui-files"]
        app.launchEnvironment["QIU_FILE_BASE"]=base; app.launchEnvironment["QIU_FILE_KEY"]=key
        app.launch(); app.tabBars.buttons["文件"].tap()
        let document=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","ui-generated.md")).firstMatch
        XCTAssertTrue(document.waitForExistence(timeout:30)); screenshot("workspace-list")
        document.tap()
        XCTAssertTrue(app.buttons["编辑文本"].waitForExistence(timeout:30)); screenshot("workspace-markdown")
        app.buttons["编辑文本"].tap()
        let editor=app.textViews["workspace-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout:5)); editor.tap(); editor.typeText(" UI edited fixture")
        app.buttons["保存"].tap()
        let ready=app.buttons["编辑文本"].waitForExistence(timeout:30)
        XCTAssertTrue(ready); guard ready else { screenshot("workspace-save-failed"); return }
        screenshot("workspace-edited")
        app.buttons["下载 / 分享"].tap()
        let copy=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","Copy")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout:10)); screenshot("workspace-share")
        if copy.exists { copy.tap() }
        else { app.swipeDown() }
        app.buttons["关闭分享"].tap()
        app.buttons["完成"].tap()
        let pdf=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","ui-generated.pdf")).firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout:5)); pdf.tap()
        XCTAssertTrue(app.buttons["下载 / 分享"].waitForExistence(timeout:30))
        XCTAssertTrue(app.otherElements["workspace-pdf"].waitForExistence(timeout:10)); screenshot("workspace-pdf-quicklook")
        app.buttons["完成"].tap()
        let image=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","ui-generated.png")).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout:5)); image.tap()
        XCTAssertTrue(app.buttons["下载 / 分享"].waitForExistence(timeout:30)); screenshot("workspace-image")
    }
    func testChatNativePickersOpenAndCancel() {
        let app=XCUIApplication(); app.launchArguments=["--ui-history"]; app.launch()
        app.buttons["跟我说"].tap()
        XCTAssertTrue(app.buttons["chat-photos"].waitForExistence(timeout:5))
        app.buttons["chat-photos"].tap()
        let cancel=app.buttons.matching(NSPredicate(format:"label IN %@",["Cancel","取消"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout:10)); screenshot("chat-native-photos-picker")
        if cancel.exists { cancel.tap() }
        app.buttons["chat-photos"].tap()
        let photo=app.images.matching(identifier:"PXGGridLayout-Info").firstMatch
        if photo.waitForExistence(timeout:8) {
            photo.tap()
            let add=app.buttons.matching(NSPredicate(format:"label IN %@",["Add","添加"])).firstMatch
            if add.waitForExistence(timeout:3) { add.tap() }
            let remove=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","移除附件")).firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout:10)); screenshot("chat-selected-photo-preview")
            if remove.exists { remove.tap() }
        } else {
            XCTFail("Imported simulator photo was not selectable"); screenshot("chat-photo-selection-failed")
            if cancel.exists { cancel.tap() }
        }
        app.buttons["chat-files"].tap()
        XCTAssertTrue(cancel.waitForExistence(timeout:10)); screenshot("chat-native-document-picker")
        let browse=app.buttons["Browse"]
        if browse.exists { browse.tap() }
        let onPhone=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","On My iPhone")).firstMatch
        if onPhone.waitForExistence(timeout:5) { onPhone.tap() }
        let qiu=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","QiuQiu")).firstMatch
        if qiu.waitForExistence(timeout:5) { qiu.tap() }
        let document=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS %@","picker-fixture")).firstMatch
        if document.waitForExistence(timeout:5) {
            document.tap()
            let open=app.buttons["Open"]; if open.waitForExistence(timeout:2) { open.tap() }
            let remove=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","移除附件 picker-fixture")).firstMatch
            XCTAssertTrue(remove.waitForExistence(timeout:10)); screenshot("chat-selected-document-preview")
            if remove.exists { remove.tap() }
        } else { XCTFail("Local Files provider fixture unavailable"); screenshot("chat-document-selection-failed"); if cancel.exists { cancel.tap() } }
        XCTAssertTrue(app.buttons["chat-photos"].waitForExistence(timeout:5))
    }
    private func selectProviderDocument(_ app: XCUIApplication, prefix: String) {
        app.buttons["chat-files"].tap()
        let cancel=app.buttons.matching(NSPredicate(format:"label IN %@",["Cancel","取消"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout:10))
        let browse=app.buttons["Browse"]; if browse.exists { browse.tap() }
        let onPhone=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","On My iPhone")).firstMatch
        if onPhone.waitForExistence(timeout:2) { onPhone.tap() }
        let qiu=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@","QiuQiu")).firstMatch
        if qiu.waitForExistence(timeout:2) { qiu.tap() }
        let document=app.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@",prefix)).firstMatch
        XCTAssertTrue(document.waitForExistence(timeout:5)); guard document.exists else { return }
        document.tap()
        let open=app.buttons["Open"]; if open.waitForExistence(timeout:2) { open.tap() }
    }
    func testProviderUnicodeEmptyAndOversizeReasons() {
        let app=XCUIApplication(); app.launchArguments=["--ui-history"]; app.launch()
        app.buttons["跟我说"].tap()
        selectProviderDocument(app,prefix:"研究")
        let remove=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","移除附件 attachment-")).firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout:10)); screenshot("provider-unicode-normalized")
        if remove.exists { remove.tap() }
        selectProviderDocument(app,prefix:"oversized-fixture")
        let oversized=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","4194305 字节")).firstMatch
        XCTAssertTrue(oversized.waitForExistence(timeout:10)); screenshot("provider-oversize-exact-reason")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","移除附件")).firstMatch.exists)
        app.buttons["关闭"].tap()
        selectProviderDocument(app,prefix:"empty-fixture")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","代码 103")).firstMatch.waitForExistence(timeout:10))
        screenshot("provider-empty-exact-reason")
    }
    func testNavigationManagementAndKeyboard() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-history"]; app.launch()
        XCTAssertTrue(app.buttons["跟我说"].waitForExistence(timeout: 10))
        screenshot("home-light")
        XCTAssertTrue(app.images["球球人物"].exists)
        app.tabBars.buttons["回看"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "验收历史")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.press(forDuration: 1.2)
        app.buttons["重命名"].tap()
        let field = app.alerts.textFields.firstMatch
        field.tap(); field.clearAndEnter("验收改名")
        app.alerts.buttons["保存"].tap()
        let renamed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "验收改名")).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 3))
        renamed.press(forDuration: 1.2); app.buttons["置顶"].tap()
        renamed.press(forDuration: 1.2); XCTAssertTrue(app.buttons["取消置顶"].exists); app.buttons["归档"].tap()
        app.buttons["已归档"].tap()
        XCTAssertTrue(renamed.waitForExistence(timeout: 3))
        renamed.press(forDuration: 1.2); app.buttons["恢复"].tap()
        app.buttons["最近"].tap()
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("验收改名")
        XCTAssertTrue(renamed.exists); screenshot("review-search")
        renamed.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 3))
        let composer = app.textViews.firstMatch
        if composer.exists { composer.tap(); composer.typeText("键盘草稿") }
        else { let f = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS %@", "跟球球")).firstMatch; f.tap(); f.typeText("键盘草稿") }
        XCTAssertTrue(app.buttons["发送"].exists); screenshot("chat-keyboard")
        app.buttons["完成"].tap()
        app.tabBars.buttons["任务"].tap(); XCTAssertTrue(app.staticTexts["当前没有进行中的任务"].exists)
        app.tabBars.buttons["我的"].tap(); app.buttons["连接设置 · 诊断日志"].tap()
        XCTAssertTrue(app.buttons["导出诊断日志"].waitForExistence(timeout: 5)); app.buttons["导出诊断日志"].tap()
        XCTAssertTrue(app.buttons["分享诊断日志"].exists); screenshot("settings-export")
    }
    func testBusyAllowsHistoryTasksSettingsAndExportInDarkLargeText() {
        let app = XCUIApplication(); app.launchArguments = ["--ui-busy", "--ui-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        XCTAssertTrue(app.buttons["跟我说"].waitForExistence(timeout: 10)); screenshot("home-dark-large")
        app.tabBars.buttons["回看"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "验收历史")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3)); row.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["发送"].isEnabled)
        app.buttons["当前任务 · 查看详情"].tap()
        XCTAssertTrue(app.buttons["手动重连"].waitForExistence(timeout: 3))
        app.buttons["返回对话"].tap()
        screenshot("busy-chat-dark-large")
        app.buttons["完成"].tap()
        app.tabBars.buttons["任务"].tap(); XCTAssertTrue(app.staticTexts["执行中心"].exists)
        app.tabBars.buttons["我的"].tap(); app.buttons["连接设置 · 诊断日志"].tap()
        app.swipeUp()
        let export = app.buttons["导出诊断日志"]
        XCTAssertTrue(export.waitForExistence(timeout: 5)); export.tap()
        XCTAssertTrue(app.buttons["分享诊断日志"].exists); screenshot("busy-settings-export")
    }
}

extension XCUIElement {
    func clearAndEnter(_ value: String) {
        let old = self.value as? String ?? ""
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + value)
    }
}
