# Build21 project/workspace switching

## Reference and permission
Android 3.8.8 `WorkspaceScreen.kt` at the bundled reference revision has an `onChooseProject` menu action and profile/project subtitle; `ProjectSelection.kt` picks the most specific matching remote path. The user's reported permission to reuse their friend's original work and existing attribution are retained. No Android runtime/auth code was imported.

## Implemented boundary
- App-managed named document projects; not OS mounts, native global project administration, process cwd changes, terminal execution isolation or model sandboxes.
- `GET /v1/app/projects` and create-only `POST {name}` use the existing app key. No deletion, arbitrary roots, home scanning or admin forwarding.
- Legacy default root is unchanged. Managed project directories are owner-only beneath hidden `.projects/<opaque-id>`; legacy paths cannot enter hidden directories. Names are NFC display metadata, never paths. IDs are generated server-side, not client filesystem paths.
- Conversation binding is optional local Codable metadata. Old chats remain default; switch is blocked for that chat's nonterminal pending run. Other navigation/settings remain available. A new chat starts at default.
- Chat and Files both display the current conversation's project. Project changes reset browsing state; preview/edit/upload capture project and connection. Selecting projects never moves past files or edits the native session/source/history.
- New nondefault submissions opt into `workspace-project-v1`. Durable exact body/key remain untouched on retry; server request-key scope/fingerprint is immutable before forwarding, and admitted run IDs retain their own project. Old v2 submissions retain their projection and bytes. Attachment placement and file-generation guidance use the captured project, not a later selector value. Source-channel delivery is unchanged.
- Owned-run artifact routes resolve only that run's project and exact explicit MEDIA/QIUQIU_FILE references. Sibling/default/hidden files, traversal, symlinks and hardlinks are excluded. Old run references still resolve against default.
- Project selection is shared-key app scope, not multi-user access isolation. The agent still has its existing tools/permissions; per-request workspace guidance cannot sandbox tools or erase earlier conversation context.

## Verification status
Tests and release evidence are tracked outside source. Real model generation/download of the Build20 default artifact is preserved by read-only regression; project generation guidance is validated with isolated native HTTP fixtures without additional model calls. Files picker repair, share extension, Skills/MCP and unrelated styling are excluded.
