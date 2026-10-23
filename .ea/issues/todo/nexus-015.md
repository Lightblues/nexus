---
schema_version: 1
id: nexus-015
title: Map GitHub status codes to typed `UploaderError` cases
status: todo
priority: medium
estimate: S
labels: [uploader, github, error-handling, feature-gap]
isolation: local
delivery: none
---

## Objective
Map GitHub's 401, 404 and 409 responses to `.invalidToken` / `.repoNotFound` /
`.fileExistsConflict` and wrap transport failures as `.network(URLError)` in
`GitHubUploader`, so the uploader banner names the condition instead of printing the raw
API payload.

## Context
- `.ea/spec/uploader.md:108-110` ("## GitHub Client") — "Errors map to a typed
  `UploaderError` enum: `.invalidToken`, `.repoNotFound`, `.fileExistsConflict`,
  `.network(URLError)`. `UploaderService` translates them into user-facing toast
  messages." The four typed cases are the contract; none of the four exists today.
- `Nexus/Features/Uploader/UploaderModels.swift:91-109` — the current enum: `.notConfigured`
  (`:92`), `.unsupportedFormat` (`:93`), `.compressionFailed(String)` (`:94`),
  `.http(Int, String)` (`:95`). `:97-108` is `errorDescription`, whose `.http` arm at
  `:106` renders `"HTTP \(code): \(body)"` — the raw payload the user sees today.
- `Nexus/Features/Uploader/GitHubUploader.swift:48-54` — the PUT path: the
  `try await URLSession.shared.data(for: req)` call at `:48`, then a non-2xx
  `throw UploaderError.http(status, bodyStr)` at `:53`. This is the throw that must become
  a status-code mapping.
- `Nexus/Features/Uploader/GitHubUploader.swift:83-88` — the DELETE path, same shape
  (`:83` call, `:87` throw). `delete(path:sha:)` has no call site today (recorded in
  `.ea/report/features-inventory.md`), so map it for consistency rather than leaving a
  second, inconsistent throw.
- `Nexus/Features/Uploader/GitHubUploader.swift:105-109` — `fetchSha`: the `:105`
  `URLSession.shared.data(for:)` call and the `:109` `throw .http(status, "")` for a
  non-200 that is not a 404.
- `Nexus/Features/Uploader/GitHubUploader.swift:26` — `let existingSha = try? await
  fetchSha(...)`. The `try?` swallows every `fetchSha` failure, so a 401 during the SHA
  lookup disappears and reappears as the PUT's 401 at `:53`. The mapping must be applied
  where the throw happens, otherwise the typed case never reaches the caller on that path.
- `Nexus/Features/Uploader/UploaderService.swift:56-103` — `upload` rethrows the client's
  error unchanged; the service adds `.notConfigured` at `:66`. The spec's sentence puts the
  typed enum in the client and the translation in `UploaderService`, so a mapping helper
  belongs next to the `HTTPURLResponse`, not in a third layer.
- `Nexus/Features/Uploader/Views/UploaderView.swift:587-591` — the catch that turns
  `error.localizedDescription` into the per-item failure; `:605-609` builds the summary
  banner from the same strings. `:620-635` is `messageBanner`. This is the only consumer of
  `errorDescription`, so it is what makes the mapping user-visible.
- `Nexus/Features/Uploader/GitHubUploader.swift:10-15` — the header comment records the
  `Authorization: Bearer <token>` choice. A 401 mapping to `.invalidToken` is about the
  response, not about changing that header; the spec's `token {pat}` spelling is a separate
  drift note recorded in the inventory, not part of this issue.
- `Nexus/Features/Uploader/GitHubUploader.swift:60` — the response `JSONDecoder().decode`
  call. A `DecodingError` here escapes as an untyped error today; whether `.network`
  should absorb it is an open question (see Boundaries).
- `project.yml:35-38` — no test target, so acceptance is a manual run against a repo and
  token you can deliberately break, plus inspection.

## Tasks
- [ ] Add `.invalidToken`, `.repoNotFound` and `.fileExistsConflict` to `UploaderError`
      (`UploaderModels.swift:91-95`) with `errorDescription` arms that name the condition
      and the fix
- [ ] Add `.network(URLError)` and use it to wrap `URLError` escapes from the three
      `URLSession.shared.data(for:)` calls (`GitHubUploader.swift:48`, `:83`, `:105`)
      instead of letting them leave `GitHubUploader` as untyped errors
- [ ] Map status → case in one place: 401 → `.invalidToken`, 404 → `.repoNotFound`,
      409 → `.fileExistsConflict`, everything else → `.http(status, body)`; apply it at all
      three throw sites (`:53`, `:87`, `:109`)
- [ ] Keep `.http(Int, String)` as the fallback for statuses with no typed case, so an
      unexpected status still reports its code and body
- [ ] Decide whether the mapping helper lives in `GitHubUploader` or as an `UploaderError`
      initialiser, and say which in the PR; do not add a third layer beyond the client and
      `UploaderService`
- [ ] Touch `UploaderService.upload` (`UploaderService.swift:56-103`) only if the mapping
      lands there — it currently rethrows unchanged, which is already the correct shape for
      a client-side mapping
- [ ] Update `.ea/spec/uploader.md:108-110` if the shipped case names differ from the four
      it names, and note in the PR that the surface is `UploaderView.messageBanner`
      (`:620-635`), not a toast

## Acceptance
- [ ] A 401 response produces a banner naming the token as the problem, not
      `HTTP 401: {…JSON…}`; verified by setting a deliberately wrong
      `uploader.github.token` and uploading
- [ ] A 404 (missing repo, or missing branch) produces a banner naming the repo/branch, not
      the raw payload
- [ ] A 409 (file exists conflict) produces a banner naming the conflict rather than the
      raw payload
- [ ] A transport failure (network off, or an unreachable host) surfaces as
      `.network(URLError)` with the underlying `URLError` intact, rather than escaping as an
      untyped error
- [ ] `grep -n "UploaderError.http" Nexus/Features/Uploader/GitHubUploader.swift` no longer
      appears as the only throw shape; each of the three sites routes through the mapping
- [ ] `UploaderError.http(Int, String)` still exists and still reports the status and body
      for a status with no typed case
- [ ] `.ea/spec/uploader.md` "## GitHub Client" and `Nexus/Features/Uploader/UploaderModels.swift`
      list the same set of error cases
- [ ] No change to the `upload_history` row or the CDN URL: the mapping affects the error
      surface only

## Boundaries
- Always: keep the raw status code and body reachable — the typed cases are for the
  user-facing message, and `.http` must remain the fallback so an unmapped status is still
  diagnosable
- Always: keep the mapping next to the `HTTPURLResponse` that carries the status; the
  service has no access to it once the error is thrown
- Always: preserve the underlying `URLError` inside `.network` so a DNS failure and a
  timeout stay distinguishable
- Never: swallow the response body for an unmapped status — `UploaderError.http`'s body is
  what makes a novel failure debuggable
- Never: map every non-2xx to `.network` — a 401/404/409 is a completed HTTP exchange with
  a meaningful status, and collapsing it into a transport error would hide the fix
- Never: change the `Authorization: Bearer` header, the endpoint shape, or the request body
  in this change; the spec's `token {pat}` spelling is a separate drift note
- Ask: whether `.network(URLError)` should also absorb `DecodingError` from the response
  decode (`GitHubUploader.swift:60`) — the spec names only `URLError`, so widening it needs
  a decision
- Ask: whether `GitHubUploader.delete(path:sha:)` should be wired up or left dormant; it
  has no call site, and mapping its errors is only worth doing if it becomes reachable
