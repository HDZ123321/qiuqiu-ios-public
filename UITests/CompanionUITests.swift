import XCTest

final class CompanionUITests: XCTestCase {
    private func screenshot(_ name: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
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
