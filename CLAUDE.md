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
                              429/5xx backoff, decode, error envelope
    DriveClient.swift         HIGH-LEVEL facades: endpoints + pagination
    SheetsClient.swift
    DocsClient.swift
    SlidesClient.swift
  Models/                     trimmed Codable models, one file per service
  Helpers/                    GoogleURL, GoogleJSON, OutputFormatter, GrahamLog
Sources/graham/               the thin CLI
  Graham.swift                @main root command
  CLISupport.swift            builds the shared GoogleAPI, log handler
  Commands/                   one file per subcommand group
Tests/GrahamKitTests/         offline tests; StubTransport + inline fixtures
Tests/CLITests/               argument-parsing tests only
```

### The two API layers

- `GoogleAPI` (low-level) is the only place that touches auth headers, retry,
  backoff, and decoding. It refreshes the token once after a 401, retries
  429/5xx with exponential backoff, and honors `Retry-After`.
- The service clients (`DriveClient`, ...) build URLs, hold pagination loops,
  and return typed models. Pagination lives ONLY here. Every list method
  threads a client-side `limit` guard through the page loop.

### The transport seam

`HTTPTransport` is a protocol with one method. Production uses
`URLSessionTransport`; tests use `StubTransport` (static JSON, in order, HTTP
599 for unmatched requests). Never mock URLSession, and never write a test
that touches the network.

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

### Write endpoints (future)

Sheets/Docs/Slides writes are mostly POST `batchUpdate` endpoints with request
bodies, not REST verbs. `GoogleAPI.sendJSON(_:method:url:body:)` exists for
this; add request-body models under `Models/` when the time comes.

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
  sends that to stderr so stdout stays clean for piping.
- Google rate-limit errors can also arrive as 403 with status
  `rateLimitExceeded`/`userRateLimitExceeded` in the error envelope. The
  current retry loop only handles 429/5xx; if 403 rate limits show up in
  practice, extend `GoogleAPI.send` to inspect the envelope status.
- Output is deterministic: JSON encoders sort keys, tables pad all but the
  last column (no trailing whitespace).
- Shared-drive items are invisible to `files.list` unless the request sets
  `supportsAllDrives=true`, `includeItemsFromAllDrives=true`, and
  `corpora=allDrives`. `DriveClient.list` sets all three, so it spans shared
  drives for both contents and global-search calls. `DriveClient.drives` lists
  the shared drives themselves (the `/drives` endpoint), and `DriveClient.root`
  fetches "My Drive" via `files.get` on the id `root`. The CLI's top-level
  `drive list` renders My Drive plus the shared drives together by mapping each
  `SharedDrive` to a `DriveFile` row with a synthetic
  `application/vnd.google-apps.drive` MIME (`SharedDrive.asDriveFile`).
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

## Commands

- Build: `swift build`
- Test: `swift test`
- Run: `swift run graham --help`
- Install: `mint install adamwulf/graham@main --force`
