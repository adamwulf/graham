---
name: graham
description: Read and write Google Drive, Docs, Sheets, and Slides from the terminal with the `graham` CLI. Use to list or find files, get file metadata, create Docs/Sheets/Slides/folders, download or export files, read and write Sheet values, edit Docs and Slides, and organize files (rename, move, star, trash). Talks to the Google Workspace REST APIs over OAuth.
---

# graham — Google Workspace from the terminal

`graham` is a command-line tool for Google Drive, Docs, Sheets, and Slides. It
speaks to the Google REST APIs over OAuth. This skill gives the minimal set of
commands to do real work. For the full flag list of any command, run it with
`--help` (for example `graham drive list --help`).

## Setup and auth (do this first)

`graham` needs OAuth credentials in a `.env` file. It looks for `.env` from the
current directory up to the filesystem root. The nearest `.env` wins. Real
environment variables win over `.env`.

The `.env` file needs three keys:

```
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REFRESH_TOKEN=...
```

- The client id and secret come from a Google Cloud OAuth client (Desktop app
  type). The one-time Google Cloud setup is in the project `README.md`.
- `graham auth login` gets the refresh token. It opens a browser for consent,
  then writes `GOOGLE_REFRESH_TOKEN` to the nearest `.env` file.
- `graham auth status` shows which credentials are set and tests a token
  refresh. Run it first to confirm auth works.

```bash
graham auth login          # one-time consent; saves the refresh token
graham auth status         # confirm the credentials work
```

**Gotcha — 7-day token expiry.** If the OAuth app is an *External* app in
*Testing* mode, the refresh token expires 7 days after it is issued. Re-run
`graham auth login` about weekly. An *Internal* app (or a Published app) has no
such expiry. If a command fails with an auth error, run `graham auth login`
again first.

## File ids

Almost every command takes a file id. Get ids two ways:

- From a `graham drive list ...` result.
- From a Google URL: the id is the long token in
  `https://docs.google.com/document/d/<id>/edit`.

For scripts, add `--format id` to a list command to print bare ids only.

## Listing and finding files

`graham drive list` has three forms:

```bash
# No id: list the top-level roots (My Drive + shared drives).
graham drive list
# With an id: list the contents of that folder or shared drive.
graham drive list <folder-or-drive-id>
# Search across ALL drives (a --query or a doc/sheet/slide --type triggers search).
graham drive list --query "name contains 'report'" --limit 20
```

Filter and shape the output:

```bash
graham drive list --type sheets              # docs | sheets | slides | folders | all
graham drive list <folder-id> --type docs
graham drive list --query "name contains 'budget'" --format json
```

- `--type` filters by kind. `--query` is a raw Drive `q` string. `--limit`
  caps the count.
- List output format is `--format table|json|jsonl|id` (default `table`).
- `graham drive list` spans shared drives, not only My Drive.

Get one file's metadata:

```bash
graham drive get <file-id> --format json
```

## Creating files

`graham drive create` is the one home for making files. The type is a
subcommand. Each prints the new file's id.

```bash
graham drive create doc "Quarterly Report"
graham drive create sheet "Budget" --parent <folder-id>
graham drive create slides "Kickoff Deck"
graham drive create folder "Project Files"
# A shortcut that points to an existing file.
graham drive create shortcut <target-file-id> --name "Report shortcut"
# A copy of an existing file (optionally rename it).
graham drive copy <file-id> --name "Quarterly Report Copy"
```

`--parent` puts the new file in a folder. Without it, the file lands in My
Drive. New Docs/Sheets/Slides files start empty; edit them with the service
commands below.

## Downloading and exporting files

A Google Workspace file (Doc/Sheet/Slides) has no raw bytes — **export** it. A
binary file (photo, PDF, ...) — **download** it.

```bash
# Export a Workspace file to another format.
graham drive export <file-id> --type pdf -o report.pdf
graham drive export <file-id> --type csv -o data.csv
# Download a binary file's raw bytes.
graham drive download <file-id> -o photo.jpg
```

- `--type` names a common format: `txt`, `md`, `csv`, `pdf`, `docx`, `pptx`,
  `xlsx`. `--mime` takes a raw MIME type for anything else (for example
  `application/rtf`). Use one, not both.
- `-o/--output` writes to a file. Without it, bytes go to stdout.

## Organizing files

```bash
graham drive rename <file-id> "New Name"
graham drive move <file-id> --to <folder-id>
graham drive star <file-id>              # mark a favorite; --off to unstar
graham drive trash <file-id>             # reversible in Drive
graham drive untrash <file-id>           # restore from trash
graham drive delete <file-id> --force    # permanent; --force is required
```

## Common per-service operations

### Sheets

```bash
graham sheets get <spreadsheet-id>                          # metadata
graham sheets values <spreadsheet-id> "Sheet1!A1:C10"       # read values
graham sheets values <spreadsheet-id> "Sheet1!A1:C10" --raw # unformatted
# Write rows. --row splits on commas; --json-rows or --tsv keep commas in a cell.
graham sheets set <spreadsheet-id> "Sheet1!A1:B2" --row "Label,Value" --row "A,10"
graham sheets append <spreadsheet-id> "Sheet1!A1" --row "C,30"   # after the table
graham sheets clear <spreadsheet-id> "Sheet1!A1:B10"            # values only
```

Sheets also has tabs, formatting, borders, sort, named ranges, conditional
format, data validation, filters, protected ranges, and charts. Run
`graham sheets --help` (and `graham sheets <group> --help`) for those.

### Docs

```bash
graham docs cat <document-id>                     # plain text
graham docs cat <document-id> --markdown          # render as Markdown
graham docs structure <document-id>               # blocks + index ranges
# Edit text. Indices are ZERO-based UTF-16 code units (the Docs API definition).
graham docs insert <document-id> --text "Hello" --at 1
graham docs delete <document-id> --from 1 --to 6
graham docs replace <document-id> --find "old" --replace "new"
graham docs images <document-id> --download ./images
```

Run `graham docs structure` first: its index ranges are what the write commands
consume. Docs also has style, paragraph, lists, tables, headers/footers,
footnotes, named ranges, page setup, and tabs — see `graham docs --help`.

### Slides

```bash
graham slides cat <presentation-id>                       # all text
graham slides list <presentation-id>                      # every element
graham slides list <presentation-id> --format json        # + geometry, ids, URLs
graham slides images <presentation-id> --download ./images
graham slides add <presentation-id> --at 2 --layout TITLE_AND_BODY
graham slides notes show <presentation-id>                # speaker notes
```

Slide and element object ids come from `graham slides list --format json`.
Slides also has element create/move/style, tables, text edits, and charts — see
`graham slides --help`.

## Index and position conventions (important)

- User-facing positions are **one-based**: slide positions, table rows and
  columns, sheet tab positions.
- Docs and Slides **text indices are zero-based** UTF-16 code units, matching
  the API. Read the current indices with `graham docs structure` before a text
  edit.

## Quick checklist for a task

1. `graham auth status` — confirm credentials work (re-`login` if not).
2. `graham drive list ...` — find the file and copy its id.
3. Run the service command (`sheets`, `docs`, or `slides`) with that id.
4. For a file with no id yet, `graham drive create ...` makes one and prints
   its id.
