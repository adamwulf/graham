# CLAUDE.md

Guidance for agents and developers working in this repository.

## What this is

`graham` is a CLI for the Google Workspace REST APIs (Drive v3, Sheets v4,
Docs v1, Slides v1). It follows the same pattern as its sibling CLIs `hunch`
(Notion) and `cirqueduci` (CircleCI): one SwiftPM package with a library that
holds all logic, plus a thin executable installed with mint.

We intentionally do NOT use Google's SDKs. Google archived its official Swift
libraries (`google-api-swift-client`, `google-auth-library-swift`), and the
third-party packages cover single services and target iOS apps. The REST APIs
are plain JSON, so the package talks to them directly with URLSession.

## Architecture

Two products, one rule: **if it can be unit-tested, it belongs in the
library**. The executable only parses arguments, calls the library, and prints.

```
Sources/GrahamKit/            the library — ALL logic lives here
  DotEnv.swift                .env loader; walks up parent dirs, nearest wins
  CredentialsResolver.swift   env-var-first, .env-fallback credential lookup
  GrahamError.swift           the one typed error enum + DecodingError detail
  HTTP/HTTPTransport.swift    protocol seam + URLSessionTransport
  Auth/
    GoogleScope.swift         OAuth scopes + CLI short names
    OAuthTokenProvider.swift  actor; caches + refreshes access tokens
    OAuthLoginFlow.swift      one-time consent flow (code exchange)
    LoopbackServer.swift      127.0.0.1 listener for the OAuth redirect
  APIs/
    GoogleAPI.swift           LOW-LEVEL: auth header, 401 refresh-retry,
                              429/5xx + 403 rate-limit backoff (honors
                              Retry-After + RetryInfo + ErrorInfo quota
                              window), decode, error envelope
    DriveClient.swift         HIGH-LEVEL facades: endpoints + pagination
    SheetsClient.swift
    DocsClient.swift
    SlidesClient.swift
  Models/                     trimmed Codable models, one file per service
  Helpers/                    GoogleURL, GoogleJSON, OutputFormatter, GrahamLog
Sources/graham/               the thin CLI
  Graham.swift                @main root command; bootstraps + drains logging
  GrahamFileLog.swift         installs the FellerBuncher file backend
  CLISupport.swift            builds the shared GoogleAPI, log handler
  Commands/                   one file per subcommand group
Tests/GrahamKitTests/         offline tests; StubTransport + inline fixtures
Tests/CLITests/               argument-parsing tests only
```

### The two API layers

- `GoogleAPI` (low-level) is the only place that touches auth headers, retry,
  backoff, and decoding. It refreshes the token once after a 401, retries
  429/5xx (and 403 rate-limit envelopes) with exponential backoff, and waits
  the longer of that backoff and any server-supplied hint. Three hint sources
  are read, and the largest wins: the `Retry-After` header, a
  `RetryInfo.retryDelay` in the error body, and — when neither is present — the
  quota window a `google.rpc.ErrorInfo` names. The winning hint gets a two-second
  boundary buffer added, so a retry lands just past Google's window rather than a
  hair before it (clock skew, network latency, and sub-second rounding otherwise
  burn a retry on the same 429). Pure backoff has no such boundary and keeps its
  bare schedule. Slides' per-minute *write* quota
  returns exactly that third shape: a bare `429 RESOURCE_EXHAUSTED` whose only
  hint is an `ErrorInfo` with `quota_unit` (`1/min/...`) and `window_start_time`
  in its `metadata`. The client waits out the time left in that window, measured
  against the server's own `Date` header (falling back to the full window when no
  `Date` is readable). Only per-second and per-minute windows are waited out; a
  per-hour or per-day quota will not clear inside a CLI run, so those fall
  through to backoff. When no hint parses at all, it still logs the raw response
  headers and body so the miss can be diagnosed after the fact.
- The service clients (`DriveClient`, ...) build URLs, hold pagination loops,
  and return typed models. Pagination lives ONLY here. Every list method
  threads a client-side `limit` guard through the page loop.

### Slides model and read facade

`SlidesModels.swift` mirrors the live Slides v1 `PageElement` union. It
currently models nine variants: group, shape, image, video, line, table, Sheets
chart, word art, and speaker spotlight, plus `.unknown` for forward
compatibility. Common geometry and alt-text fields live on `PageElement`;
nested groups recursively contain more page elements.

`Presentation.elementRows` is the detailed read facade used by `slides list`.
It flattens groups depth-first while retaining `parentObjectId` and nesting
depth, and extracts direct text, links, alt text, raw geometry, and image URLs.
`Presentation.imageRows` recursively filters images for `slides images`.
`Presentation.findElement(objectId:)` finds one element anywhere in the deck,
recursing into nested groups; the geometry edits use it to read an element's
current transform before writing. Keep extraction and flattening logic in
`GrahamKit`; commands only fetch and render.

### The transport seam

`HTTPTransport` is the only network seam. Production uses
`URLSessionTransport`; tests use `StubTransport` (static responses in order,
HTTP 599 for unmatched requests). Never mock URLSession, and never write a test
that touches the network.

`SlidesClient` has a second injected transport specifically for image
`contentUrl` downloads. These short-lived URLs are pre-authorized and live on a
Google user-content host, so downloads must use a plain GET with **no OAuth
`Authorization` header**. Never route a `contentUrl` through `GoogleAPI`, which
would attach the API bearer token. Tests must stub both API requests and image
bytes.

### Auth model

Google uses OAuth2, unlike hunch's single static token:

- `.env` holds `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`,
  `GOOGLE_REFRESH_TOKEN`. Process environment beats `.env`.
- `graham auth login` runs the consent flow: loopback server on an ephemeral
  127.0.0.1 port, browser consent, code exchange with `access_type=offline`
  and `prompt=consent`, then saves the refresh token to the nearest `.env`
  file (walking up from the working directory) via `DotEnv.setValue`. It
  upserts `GOOGLE_REFRESH_TOKEN` — replacing an existing line, or appending a
  new one — so a re-login updates cleanly. If no `.env` exists it creates one
  in the working directory; if the write fails it falls back to printing the
  line for the user to paste.
- `OAuthTokenProvider` (an actor) turns the refresh token into short-lived
  access tokens on demand and caches them until near expiry.

## Recipes

### Add a new endpoint

1. Add a method to the right service client. Build the URL with
   `GoogleURL.build` (query) and `GoogleURL.escapePathComponent` (path).
2. Add or extend a model in `Models/`. Make every field optional except true
   invariants (like `id`). Google's APIs evolve; decode defensively.
3. If the endpoint lists items, loop on `nextPageToken` and thread a `limit`.
4. Add a `StubTransport` test with a realistic JSON fixture, including one
   pagination case if the endpoint paginates.
5. If the CLI needs it, add a subcommand that calls the facade and renders
   with `OutputFormatter` (or a `--json` flag for single documents).

### Add a new list output

Conform the model to `GrahamRow` (`tableColumns`, `tableValues`, `idValue`)
next to the model. Then any command can render it in all four formats.

### Add a write endpoint

Drive file creation already uses `GoogleAPI.sendJSON`. Slides writes go
through `SlidesClient.batchUpdate` and the `SlidesBatchUpdateRequest` union
(`Models/SlidesBatchUpdateModels.swift`); a new Slides operation joins that
union as a new case. Sheets has its own `SheetsBatchUpdateRequest` union in
`Models/SheetsBatchUpdateModels.swift`, beginning with `addChart`. Docs follows
the same shape with `DocsBatchUpdateRequest` in
`Models/DocsBatchUpdateModels.swift`, beginning with `insertText`,
`deleteContentRange`, and `replaceAllText`; every Docs write type is prefixed
`Docs` because `GrahamKit` is one module and bare names like `InsertText`
already belong to Slides.

1. Define typed request and response models under `Models/`. Request fields
   should be required when the operation requires them; response fields should
   remain optional unless they are true invariants.
2. Add a high-level service-client method that owns the endpoint, escaped path,
   HTTP method, and request body. For Slides, keep one extensible request union
   so later element, geometry, text, and appearance operations share the same
   batch-update path.
3. Test the exact method, URL, encoded JSON body, decoded replies, empty replies,
   and Google error propagation through `StubTransport`.
4. Add a thin CLI command only after the client behavior is covered.
   User-facing positions are one-based: slide positions, table rows and
   columns, and link slide targets. Text indices are the exception: they stay
   zero-based (UTF-16 code units), matching the API. Translate one-based to
   zero-based in `GrahamKit`, not in the command.

Never update response fixtures or `Package.resolved` by hand to simulate a
write. Tests remain offline and exercise the real encoding path.

## Gotchas (learned from hunch/cirqueduci, kept here on purpose)

- `URLComponents` leaves `+` unescaped, but Google reads `+` as a space.
  `GoogleURL.build` force-escapes `+` to `%2B` — page tokens are base64-like
  and break without this. Do not build query strings by hand.
- Resolve credentials ONCE at command start (`CLI.makeAPI()`); pass injectable
  `environment` and `startingIn` parameters so tests never depend on the
  machine's real environment.
- Surface decode failures with `GrahamError.decodingDetail` — it names the
  JSON path of the failing field. Keep this working; it pays for itself the
  first time Google adds a field.
- The library never prints. It logs through `GrahamLog.handler`; the CLI
  installs a handler (`CLI.installLogHandler`) that fans each line to two
  sinks: stderr (so the lines are live and stdout stays clean for piping) and
  a swift-log `Logger` that the FellerBuncher backend persists to
  `~/Library/Logs/graham/graham.log` (logfmt, size-rotated). Only the
  executable links swift-log/FellerBuncher; the library keeps the seam. The
  `@main` `Graham.main` bootstraps the file backend first and `drain()`s it on
  both the success and error exit paths — a short-lived CLI loses the buffered
  tail otherwise.
- Google rate-limit errors can also arrive as 403 with status
  `rateLimitExceeded`/`userRateLimitExceeded` in the error envelope.
  `GoogleAPI.send` now inspects the envelope status and retries those 403s just
  like a 429; `GoogleErrorEnvelope.isRateLimit` holds the status check and
  `retryDelaySeconds` parses any `RetryInfo` the body carries.
- Not every rate limit carries a `RetryInfo`. Slides' per-minute *write* quota
  returns a bare `429` whose only timing hint is a `google.rpc.ErrorInfo`
  naming the quota window in its `metadata`: `quota_unit` (`1/min/...`) and
  `window_start_time` (epoch seconds).
  `GoogleErrorEnvelope.quotaWindowRetrySeconds(serverNow:)` computes the raw time
  left in that window (`window_start_time + windowLength - serverNow`), and
  `GoogleAPI.serverEpoch` reads `serverNow` from the response `Date` header so
  the wait never depends on the local clock. The two-second boundary buffer is
  NOT baked into this value — `GoogleAPI.send` adds it once to whichever hint
  wins, so all three hint sources share a single buffer rather than each keeping
  its own.
  `GoogleErrorEnvelope.windowSeconds(forQuotaUnit:)` only maps `s`/`min` (the
  short windows worth waiting out) — a per-hour or per-day quota stays `nil` and
  falls back to backoff. The old 1s/2s/4s exponential backoff never cleared this
  quota, because its window is a full minute; the client now waits out the
  window instead.
- Output is deterministic: JSON encoders sort keys, tables pad all but the
  last column (no trailing whitespace).
- Shared-drive items are invisible to `files.list` unless the request sets
  `supportsAllDrives=true`, `includeItemsFromAllDrives=true`, and
  `corpora=allDrives`. `DriveClient.list` sets all three, so it spans shared
  drives for both contents and global-search calls. `DriveClient.drives` lists
  the shared drives themselves (the `/drives` endpoint), and `DriveClient.root`
  fetches "My Drive" via `files.get` on the id `root`. `DriveClient.roots`
  combines My Drive plus the shared drives into one `[DriveFile]`, mapping each
  `SharedDrive` to a row with a synthetic `application/vnd.google-apps.drive`
  MIME (`SharedDrive.asDriveFile`). `DriveClient.browse` holds the `drive list`
  routing (id → contents, no id + no query + all/folders → roots, else global
  search); the CLI just calls `browse` so all the routing is unit-tested.
- `DriveFileType` lives in `GrahamKit` (no ArgumentParser import). Its
  `ExpressibleByArgument` conformance lives in the CLI target next to
  `OutputFormat`'s. Building a Drive `q` goes through `DriveClient.buildQuery`,
  which backslash-escapes any `'`/`\` inside a quoted id — never interpolate a
  raw id into a `q` clause.
- The default OAuth scopes (`GoogleScope.all`) include the full `drive` scope,
  which Google classes as a **restricted** scope. Two consequences: an External
  OAuth app cannot publish to Production without Google's verification review,
  and an External app left in **Testing** mode issues refresh tokens that
  expire 7 days after issue (so `graham auth login` must be re-run about
  weekly). If a write feature only needs files graham creates or opens, adding
  a `drive.file` scope (not restricted) to `GoogleScope` avoids both problems.

- `drive create` uses `DriveCreateType`, not the broader listing-only
  `DriveFileType`. It sends the name and Google Workspace MIME type in a JSON
  body through `DriveClient.create`; it does not put names in URLs. Without a
  parent, new files land in My Drive.
- Slides batch updates use zero-based insertion indices based on the slide order
  before a move, while graham displays and accepts final slide positions as
  one-based. Resolve the source index and translate at the high-level client
  boundary. A batch response can contain empty replies for operations such as
  move/delete, so do not require every request to return an object ID.
- The Slides `update*Properties` operations take a `fields` mask string of
  comma-separated paths relative to the properties root (the root itself is
  not spelled). The client builds one deterministic mask path per provided
  parameter, in a fixed documented order, and the tests assert the exact
  string. Updating a fill/outline/shadow implicitly sets its `propertyState`
  to `RENDERED`; clearing one means masking `propertyState` with
  `NOT_RENDERED`.
- `ImageProperties` is almost entirely read-only in the Slides API:
  brightness, contrast, transparency, crop, recolor, and shadow CANNOT be
  written; only the image outline and link can. Do not plan or model writes
  for the read-only fields.
- `updatePageElementTransform` RELATIVE mode left-multiplies (result =
  update × existing) and does NOT convert units between the two matrices. The
  computed geometry edits therefore read the element first, do the math in
  the element's native unit (usually EMU; 12700 EMU per point), and send one
  precomputed ABSOLUTE transform — Google's own recommendation. The pure
  matrix helpers live on `ElementTransform`.
- Element creation generates client-side object ids (`graham-` + UUID, which
  fits Google's 5–50 char id rules) so that a create and its follow-up edits
  (for example text-box + insertText) can share one atomic batch. Reply
  object ids are still preferred when Google returns them.
- Docs `updateTableRowStyle` rejects `tableHeader` (`400` "Unallowed field:
  tableHeader") even though the `TableRowStyle` schema lists it — a row's header
  designation is read-only once the table exists. `DocsTableRowStyle` models
  only `minRowHeight` and `preventOverflow`; mark headers with `pinTableHeaderRows`
  (`docs table pin-headers`) instead.

## Commands

- Build: `swift build`
- Test: `swift test`
- Run: `swift run graham --help`
- Install: `mint install adamwulf/graham@main --force`
