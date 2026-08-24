# Roadmap

The plan for `graham`. See `CLAUDE.md` for the architecture and the recipes
that show how to add each kind of feature.

## Done

- **OAuth setup and login.** `graham auth login` runs the consent flow and
  saves `GOOGLE_REFRESH_TOKEN` to the nearest `.env` (see `DotEnv.setValue`).
  `graham auth status` confirms a live token refresh.
- **Live connection validated** against a real Google account.
- **Read commands.** Drive (`list`, `get`, `export`, `download`), Sheets
  (`get`, `values`), Docs (`cat`), Slides (`cat`).
- **Drive navigation and type filter.** `graham drive list` shows the top-level
  roots (My Drive plus shared drives); `graham drive list <id>` shows the
  contents of a folder or shared drive; `graham drive list --query …` searches
  across all drives. `--type docs|sheets|slides|folders|all` works in every
  form and combines with `--query`, `--limit`, and `--format`.

## Known follow-ups and caveats

- **External-app token expiry.** The OAuth app is External and stays in Testing
  mode, so refresh tokens expire 7 days after issue. Re-run `graham auth login`
  about weekly. See the note in `README.md`.
- **Optional narrower scope.** The default scopes include the full `drive`
  scope (a Google "restricted" scope), which forces verification to publish to
  Production. If future write features only touch files graham creates or opens,
  add a `drive.file` scope to `GoogleScope` to avoid both the verification and
  the 7-day expiry.
- **Multiple accounts.** One `.env` holds one refresh token (one account). To
  use several accounts, keep a separate `.env` (with its own
  `GOOGLE_REFRESH_TOKEN`) in each working directory; the nearest one wins.

## Planned features

### Write path (the frontier)

Writes are mostly POST `batchUpdate` endpoints with request bodies.
`GoogleAPI.sendJSON(_:method:url:body:)` already exists; add request-body models
under `Models/` as each lands.

1. **Sheets write** — set and append cell values (`values.update`,
   `values.append`), then `batchUpdate` for structure. Recommended first: it is
   the simplest write shape and validates the whole write path.
2. **Drive write** — create a folder, upload a file, rename/move, and share
   (permissions).
3. **Docs write** — `batchUpdate` to insert and replace text.
4. **Slides write** — `batchUpdate` to add slides and text.

### Read enhancements

- **Sheets to CSV** — export a range or a whole sheet as CSV.
- **Docs / Slides text extraction** — cleaner plain-text output from `cat`.
- **Richer `drive list`** — show owners, filter "shared with me", and print a
  folder path (breadcrumb) for an id.

## How new work fits the architecture

Every feature is one cohesive unit: a method on the right service client (with
pagination kept in the client), a defensive model under `Models/`, a
`StubTransport` test with a realistic fixture, and — if the CLI needs it — a
thin subcommand that renders with `OutputFormatter`. Nothing in the library
prints or touches the network in tests. Follow the recipes in `CLAUDE.md`.
