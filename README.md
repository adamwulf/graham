# graham

A command-line tool for Google Drive, Docs, Sheets, and Slides.

Named after Graham's number — a contrast to the googol that named Google.

## What works today

- **Auth** — OAuth login that saves the refresh token to `.env`, and a status
  check.
- **Drive** — navigate the top-level drives, list a folder or shared drive,
  search across all drives, and filter by type; get metadata; export and
  download files; create empty Docs, Sheets, and Slides files.
- **Sheets and Docs** — read a spreadsheet and its values; read a document.
- **Slides** — read presentation text; list every page element with its type,
  geometry, text, links, and alt text; list or download every image, including
  images nested in groups; add, move, and delete slides through the shared
  `presentations.batchUpdate` write path; create text boxes, images, videos,
  lines, tables, and Sheets charts; group and ungroup elements; move, scale,
  rotate, transform, and reorder elements.

See `ROADMAP.md` for the remaining Slides editing work. The next milestone is
editing element appearance.

## Install

```bash
mint install adamwulf/graham@main --force
```

## Google Cloud setup (one time)

1. Create a project at https://console.cloud.google.com/projectcreate (the
   project picker's **New project** button goes to the same page).
2. Enable four APIs from the API Library: Drive API, Sheets API, Docs API,
   Slides API.
3. Configure the **OAuth consent screen** (APIs & Services → OAuth consent
   screen). Google requires this before it lets you create a client.
   - **Audience:** choose **Internal** if every account that will use graham is
     in your Google Workspace organization; otherwise choose **External**.
   - For an **External** app, add each Google account you will use under **Test
     users** — while the app stays in Testing, only those accounts can log in.
4. Create an OAuth client ID of type **Desktop app** (APIs & Services →
   Credentials → Create credentials → OAuth client ID).
5. Put the client ID and secret in a `.env` file:

```
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
```

`graham` searches for `.env` from the current directory up to the filesystem
root. The nearest `.env` wins, and real environment variables win over `.env`.

6. Log in — graham stores the refresh token for you:

```bash
graham auth login
# a browser window opens; approve access. graham writes
# GOOGLE_REFRESH_TOKEN=... to the nearest .env file.
graham auth status
```

### Note for External apps

An External app in **Testing** mode issues refresh tokens that **expire after
7 days**, so you re-run `graham auth login` about weekly. Publishing the app to
Production removes the expiry, but because graham requests the full `drive`
scope (a Google "restricted" scope), Publishing requires Google's verification
review.

## Usage

```bash
# Navigate Drive. With no ID, list the top-level roots (My Drive + shared drives).
graham drive list
# List the contents of one folder or shared drive.
graham drive list <folder-or-drive-id>
# Filter by type in any form: docs, sheets, slides, folders, or all (default).
graham drive list --type sheets
graham drive list <folder-id> --type docs
# Search across all drives (a query, or a docs/sheets/slides type, triggers a global search).
graham drive list --query "name contains 'report'" --limit 20

graham drive get <file-id> --format json
graham drive export <file-id> --mime application/pdf -o report.pdf
# Create an empty Google Workspace file and print its new id.
graham drive create "Quarterly Report" --type docs

graham sheets get <spreadsheet-id>
graham sheets values <spreadsheet-id> "Sheet1!A1:C10"

graham docs cat <document-id>
graham slides cat <presentation-id>
# List every element; JSON includes raw geometry, links, alt text, and image URLs.
graham slides list <presentation-id>
graham slides list <presentation-id> --format json
# List image metadata, or download every image under safe deterministic names.
graham slides images <presentation-id>
graham slides images <presentation-id> --download ./images
# Add a slide (a BLANK slide at the end by default) and print its object id.
graham slides add <presentation-id>
graham slides add <presentation-id> --at 2 --layout TITLE_AND_BODY
# Create a text box (empty by default) and print its object id.
graham slides create textbox <presentation-id> <slide-id> --text "Hello"
# Create other elements on a slide (geometry is in points; slide ids come from `slides list --format json`).
graham slides create image <presentation-id> <slide-id> --url https://example.com/pic.png
graham slides create video <presentation-id> <slide-id> --id dQw4w9WgXcQ --source youtube
graham slides create line <presentation-id> <slide-id> --category straight
graham slides create table <presentation-id> <slide-id> --rows 3 --columns 4
graham slides create chart <presentation-id> <slide-id> --spreadsheet <spreadsheet-id> --chart-id 12345 --linked
# Group two or more elements (prints the new group id), or ungroup one or more groups.
graham slides group <presentation-id> <child-object-id> <child-object-id>
graham slides ungroup <presentation-id> <group-object-id>
# Edit element geometry in points; object ids come from `slides list --format json`.
graham slides element move <presentation-id> <object-id> --to-x 100 --to-y 75
graham slides element scale <presentation-id> <object-id> --by 1.5
graham slides element rotate <presentation-id> <object-id> --by 90
graham slides element transform <presentation-id> <object-id> --translate-x 10 --unit pt --relative
graham slides element reorder <presentation-id> <object-id> --to front
# Move one slide to a one-based final position (as shown by cat and list).
graham slides move <presentation-id> <slide-id> --to 1
# Delete one slide by its exact object id.
graham slides delete <presentation-id> <slide-id>
```

`graham drive list [<id>]` has three forms:

- **No `<id>`, no `--query`, `--type all` or `folders`** — the top-level roots:
  "My Drive" plus every shared drive you can see.
- **No `<id>`, but a `--query`, or `--type docs|sheets|slides`** — a global
  search across all drives.
- **`<id>` given** — the contents of that folder or shared drive.

All forms accept `--type`, `--query`, `--limit`, and `--format` and combine
them.

List commands support `--format table|json|jsonl|id`.

## Development

- `GrahamKit` is the library with all logic; `graham` is a thin CLI on top.
- `swift test` runs the full offline test suite; no test touches the network.
- See `CLAUDE.md` for the architecture and the extension recipes.
- See `ROADMAP.md` for the status and the planned next steps.
