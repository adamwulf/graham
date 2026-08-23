# sergey

A command-line tool for Google Drive, Docs, Sheets, and Slides.

## Install

```bash
mint install adamwulf/sergey@main --force
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

`sergey` searches for `.env` from the current directory up to the filesystem
root. The nearest `.env` wins, and real environment variables win over `.env`.

5. Log in and store the refresh token:

```bash
sergey auth login
# a browser window opens; approve access, then copy the printed
# GOOGLE_REFRESH_TOKEN=... line into your .env
sergey auth status
```

## Usage

```bash
sergey drive list --query "name contains 'report'" --limit 20
sergey drive get <file-id> --format json
sergey drive export <file-id> --mime application/pdf -o report.pdf

sergey sheets get <spreadsheet-id>
sergey sheets values <spreadsheet-id> "Sheet1!A1:C10"

sergey docs cat <document-id>
sergey slides cat <presentation-id>
```

List commands support `--format table|json|jsonl|id`.

## Development

- `SergeyKit` is the library with all logic; `sergey` is a thin CLI on top.
- `swift test` runs the full offline test suite; no test touches the network.
- See `CLAUDE.md` for the architecture and the extension recipes.
