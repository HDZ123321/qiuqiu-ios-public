# QiuQiu iOS — Build 10 candidate

Native SwiftUI client for a user-configured Hermes-compatible server. iOS 16+.
This public repository is a clean source snapshot, not the private development history.
No server deployment, credentials, personal records or private checkpoint documents are included.

## Status and acceptance boundaries

This is an intermediate port, **not full Android feature or visual parity**.
Source includes chat/Runs controls, local conversation management, local-only diagnostic export,
scoped workspace and attachment handling, opt-in cron management, admitted-run history,
on-device voice-to-editable-text and scoped server-session restore.
The latter feature candidates require compile/regression/UI acceptance; see the exact Actions run rather than interpreting source presence as working acceptance.
The existing Files picker defect remains unresolved and its repair is paused. No picker repair is claimed.
Voice requires Apple on-device recognition support and explicit permission; preview/edit/manual send is required. It is not full voice conversation or TTS. Physical-device speech is unverified.
Session/cron features require separately reviewed, opt-in server support and are not enabled by publishing this app.

## Build and tests

On macOS with Xcode and Homebrew: `brew install xcodegen`, `xcodegen generate`, then
`xcodebuild -project QiuQiu.xcodeproj -scheme QiuQiu -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`.
The manually dispatched macOS workflow runs Swift tests, isolated backend fixtures, simulator UI smoke tests, exports xcresult screenshots, and packages a real arm64 iPhoneOS unsigned IPA only after its gates pass.
No private source clone, signing secrets, live endpoint or model request is needed. Public Hermes source is fetched at a pinned revision only for native contract fixture tests.
Live credential-dependent tests are excluded from the public acceptance job; picker tests are retained as source but excluded from this smoke gate because their defect is explicitly unresolved, not falsely declared passing.

Unsigned IPA requires user-side signing before installation. Compilation, simulator acceptance, phone installation and real server connectivity are separate checks. Artifact SHA256 and source revision are emitted by CI.

## Privacy and server boundary

Enter your own HTTPS endpoint, bearer token and model in the app settings. Keychain stores connection settings; local application storage holds conversations. Diagnostic export is local-only, bounded and metadata-oriented, not telemetry. Review chat content before sharing.
Do not commit credentials or deployment configurations. `scripts/restricted_proxy.py` is optional generic server-boundary source, **not a deployed service**. It accepts `QIUQIU_CONFIG_DIR` and `QIUQIU_WORKSPACE_DIR` for operator-selected local paths; it binds loopback only. Cron and session routes are opt-in. Do not point tests at real user jobs or sessions.

## Rights and attribution

See `LICENSE` and bundled `Resources/SourceAttribution.txt`. The user states the Android author/friend permitted reuse of original UI/code/artwork. This does not establish a general upstream open-source license or grant rights in unrelated third-party material. No Android third-party fonts, icons or runtime libraries are copied into this snapshot. Apple SDK/system symbols remain subject to Apple's terms.
