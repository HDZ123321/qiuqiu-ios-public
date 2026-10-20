# Build22 signing and share capability

This is a genuine **unsigned iPhoneOS candidate**, not evidence that a particular self-signing setup supports App Groups. The user named **lcsign** and a self-signed certificate. Neither fact proves an authorized provisioning profile or a working group container. No claim of lcsign compatibility is made; no certificate, password or paid Apple purchase is required by this project delivery.

## Configuration and signing contract

- Host bundle: `org.hermesclient.qiuqiu`
- Embedded extension: `PlugIns/QiuQiuShare.appex`, bundle `org.hermesclient.qiuqiu.share`
- Default configurable group: `group.org.hermesclient.qiuqiu` (`QIU_SHARE_APP_GROUP` in `project.yml`). This string alone does not register or authorize a group.
- Host and extension each have explicit `com.apple.security.application-groups` entitlements. Each Info.plist has the matching resolved `QiuShareAppGroup` value.
- The re-signer must preserve the embedded extension and sign **both** executables. Both actual profiles/entitlements must permit the **same actual App Group**. If identifiers are remapped, both entitlements and both Info keys must remain aligned. A certificate alone is insufficient.
- App Groups availability is account/profile/signing-tool dependent; this document does **not** assert paid membership is necessary.
- Unsigned binaries have no effective signed entitlement. Intended entitlement files accompany the candidate separately; copying a plist into a package cannot itself grant capabilities.

## Runtime gate (fail closed)

Each process calls Apple's `containerURL(forSecurityApplicationGroupIdentifier:)` and performs an actual disposable read/write canary. The diagnostic reports support/unavailability, not private filesystem paths. Host canary success alone does not prove extension access to the same container: a real shared item appearing in the host is the end-to-end gate.

If unavailable, the extension can show incoming content but disables Save and says:

> 当前签名未启用共享容器，无法交接。请保留原内容并取消；主 App 与分享扩展须获准使用同一个 App Group。

It never substitutes a clipboard or private openURL/responder-chain trick, never pretends a failed save succeeded, and never deletes the source material. Return to the original app with Cancel.

## User flow and limits

1. In another app choose Share → 保存到球球. Review official NSItemProvider text, web URL, images or supported documents.
2. Explicitly tap 保存到球球. Only a complete atomic local inbox commit yields success. No network, model, shared credentials or auto-launch.
3. Manually open 球球 → 我的 → 分享收件箱. Preview, choose a new/existing idle chat and its project, explicitly import a **durable local draft**.
4. Open that draft, review/edit, then explicitly send with the normal chat transport. Ordinary composer text and quotation remain separate and untouched.

At most four providers/files; attachment aggregate and each document ≤4 MiB; text ≤64 KiB. Supported document types follow existing chat attachment allowlist (UTF-8-style text types, PDF and supported images), not arbitrary Office/audio archives. Images use the existing pixel-bounded ImageIO normalizer; source decode input ≤64 MiB. Unsupported/failed/excess items reject the entire intake, never silently skip or truncate. No web URL fetching.

Inbox capacity is 16 committed items; after seven days import is rejected and the user is instructed to share again. Expired items remain visibly deletable rather than being silently evicted. Capacity bounds retained committed bytes; no automatic raw-name logging. Files use opaque UUID names and a versioned manifest; directory-FD anchored no-follow reads reject symlinks, hardlinks, unsafe sizes and incomplete payloads. Save stages privately then atomically renames the directory. A crash during staging is not reported as success. Draft persistence commits before inbox acknowledgement; replay identities avoid repeated import after cleanup failure. Cancelling preview does not remove inbox data. A target pending run, conflicting share draft or changed connection fails visibly without overwrite.

## Acceptance boundary

macOS Swift/core tests, iOS provider tests, system Safari share surface, host UI and real arm64 packaging are separate gates recorded in CI evidence. Simulator group behavior is **not** proof of lcsign/device provisioning. Physical-device installation, extension visibility and actual host/extension group handoff remain unverified until exercised with the user's signing setup. Do not label this full device acceptance based on a green simulator run.
