# Reply presentation and interaction contract

## Supported

- Tables, blockquotes, inline Markdown links, selectable prose, fenced code (horizontal scrolling and copy), and uncapped vertically scrolling messages use semantic system fonts / Dynamic Type.
- Explicit `MEDIA:/absolute/path` outputs on app-owned Runs can deliver image/document bytes **only inside the existing dedicated workspace**. The read-only artifact API supplies opaque IDs, not server paths. Preview uses downloaded bytes; sharing uses a protected local file. Old messages retain optional run provenance.
- Artifact types: PNG/JPEG/GIF/WebP, PDF, UTF-8 text/Markdown/CSV/JSON. Maximum 4 MiB each, 16 referenced files. Symlinks, hidden path components, traversal, arbitrary home paths and remote URLs are rejected. No remote image is fetched automatically, no bearer is forwarded to a third-party host, and redirects are refused.
- Native operation approval uses the existing `POST /v1/runs/{run_id}/approval` contract, one exact `request_id`, and only advertised `once` / `deny`. UI requires explicit confirmation and rechecks request identity. Broader grants and resolve-all remain rejected by the restricted boundary. Readback, not HTTP acceptance alone, updates task status.

## Explicit native limits

Installed native Runs has approval callbacks but no `clarify.request` event or clarification-answer route/callback. The general clarify tool exists on other Hermes surfaces, not this transport. No invented structured choices or waiting-answer control is provided. **Answer / supplement** prepares a normal next user-message draft in the same conversation; the user must review and press Send. It does not unlock a blocking native clarification. A currently active run remains busy.

Native OpenAI final-response media conversion supports image data URLs, but Runs final output retains raw MEDIA references. The scoped artifact bridge is therefore required. Generated files outside the dedicated workspace remain unavailable; this is deliberately not a home-directory file browser. Previously imported transcripts without a known owned run cannot grant artifact access.

## Build17 conversation file index

The conversation header opens a read-only list aggregated from the existing authenticated per-run artifact API. Only persisted assistant-message `artifactRunID` provenance contributes; duplicate opaque artifact IDs appear once, with a real local message UUID for jump-back. Browsing never admits/resumes a run or changes the pending stop target. A deleted message or changed connection fails closed. The list has loading, refresh, empty, unavailable and partial-error states.

Names and MIME types come from the restricted artifact response. The existing API does not expose byte counts: sizes are explicitly unknown until an actual bounded download verifies them. No backend scan, uploaded-phone-attachment index or cross-channel historical path inference is added. Older imported conversations without an owned-run mapping show unavailable rather than invented entries. Existing artifact authorization and dedicated-workspace limits are unchanged.

## Acceptance boundaries

Synthetic-only loopback fixtures exercise actual URLSession downloads, preview/share UI and approval POST/readback. Native approval-handler integration uses temporary HERMES_HOME and a synthetic waiter, no model call. Physical installation, real inference and mobile-network reachability are separate gates. Public endpoint and credentials are never embedded in source or artifacts.
