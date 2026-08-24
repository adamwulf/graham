# graham

A command-line tool for Google Drive, Docs, Sheets, and Slides.

Named after Graham's number — a contrast to the googol that named Google.

## Install

```bash
mint install adamwulf/graham@main --force
```

## Google Cloud setup (one time)

1. Create a project at https://console.cloud.google.com/
2. Enable the APIs you need: Drive API, Sheets API, Docs API, Slides API.
3. Create an OAuth client ID of type **Desktop app** (APIs & Services → Credentials).
4. Put the client ID and secret in a `.env` file:

```
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
```

`graham` searches for `.env` from the current directory up to the filesystem
root. The nearest `.env` wins, and real environment variables win over `.env`.

5. Log in and store the refresh token:

```bash
graham auth login
# a browser window opens; approve access. graham saves
# GOOGLE_REFRESH_TOKEN=... to the nearest .env file for you.
graham auth status
```

## Usage

```bash
graham drive list --query "name contains 'report'" --limit 20
graham drive get <file-id> --format json
graham drive export <file-id> --mime application/pdf -o report.pdf

graham sheets get <spreadsheet-id>
graham sheets values <spreadsheet-id> "Sheet1!A1:C10"

graham docs cat <document-id>
graham slides cat <presentation-id>
```

List commands support `--format table|json|jsonl|id`.

## Development

- `GrahamKit` is the library with all logic; `graham` is a thin CLI on top.
- `swift test` runs the full offline test suite; no test touches the network.
- See `CLAUDE.md` for the architecture and the extension recipes.
