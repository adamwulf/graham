# graham

A command-line tool for Google Drive, Docs, Sheets, and Slides.

Named after Graham's number — a contrast to the googol that named Google.

## What works today

- **Auth** — OAuth login that saves the refresh token to `.env`, and a status
  check.
- **Drive** — navigate the top-level drives, list a folder or shared drive,
  search across all drives, and filter by type; get metadata; export and
  download files; create folders and empty Docs, Sheets, and Slides files; copy files;
  move files to trash; and permanently delete files.
- **Sheets and Docs** — read a spreadsheet (with frozen row / column counts) and
  its values (formatted, raw, or as formulas, one range or several at once);
  write cell values from comma rows, a JSON array, or tab-separated stdin; append
  rows after a table; clear a range; add, rename, and delete tabs; freeze rows
  or columns and resize them; format a range (bold, text and background color,
  font family and size, number type and pattern, alignment — each set, toggled,
  or cleared) and draw cell borders; merge and unmerge cells, sort ranges,
  auto-size dimensions, and name ranges (add, list, delete); add boolean and
  gradient (color-scale) conditional-format rules and delete them, set and clear
  data validation, turn on basic filters
  and add filter views, and add and delete protected ranges; add, update, move,
  and delete charts (basic, pie, combo, histogram, scorecard, or candlestick; on
  a new sheet or as an overlay) and list them; and run a live end-to-end smoke
  test of the Sheets command surface; read a document,
  render it as Markdown,
  and list its block structure with index ranges; list or download its images;
  create a blank document; and through the shared `documents.batchUpdate` write
  path insert, delete, and replace text, style text and paragraphs, manage
  bulleted and numbered lists, edit table structure (insert and delete rows
  and columns, merge and unmerge cells, and pin header rows), style tables
  (cell background, borders, padding, and alignment; row height, header, and
  overflow; and column width), edit structure and images (insert page and
  section breaks, insert an inline image from a URI, and replace an image),
  manage headers, footers, and footnotes
  (create and delete headers and footers, and create a footnote with optional
  text), fill templates with named ranges (create, list, delete, and replace
  the content of a named range by id or name), set document-wide page style
  (page size, margins, first-page and even-page header/footer flags, background,
  and page mode), set the style of the sections a range overlaps (margins, page
  numbering, direction, and column separator), and run a live end-to-end smoke
  test of the complete Docs command surface.
- **Slides** — read presentation text; list every page element with its type,
  geometry, text, links, and alt text; list or download every image, including
  images nested in groups; add, move, and delete slides through the shared
  `presentations.batchUpdate` write path; create text boxes, images, videos,
  lines, tables, and Sheets charts; group and ungroup elements; move, scale,
  rotate, transform, and reorder elements; style shape fills, outlines, and
  shadows; style lines and videos; edit table rows, columns, merged cells, and
  borders; refresh linked charts; and insert, delete, and style text and
  paragraphs, manage bullets, and set links; set or clear element alt text;
  read, set, and clear speaker notes; list presentation layouts and create
  slides from an exact layout id; delete any page element by exact id; and run
  a live end-to-end smoke test of the complete command surface.

See `ROADMAP.md` for future work.

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
# Export a Google Workspace file to another format, or download a binary file's
# raw bytes (Docs/Sheets/Slides have no bytes to download — export them).
graham drive export <file-id> --mime application/pdf -o report.pdf
graham drive download <file-id> -o photo.jpg
# Create an empty Google Workspace file and print its new id. The type is a
# subcommand: doc, sheet, slides, or folder. --parent places the new file in a
# folder; without it the file lands in My Drive.
graham drive create doc "Quarterly Report"
graham drive create sheet "Budget" --parent <folder-id>
# Create a folder.
graham drive create folder "Project Files"
# Create a shortcut that points to an existing file.
graham drive create shortcut <target-file-id> --name "Report shortcut"
# Copy a file, optionally renaming the copy, and print its new id.
graham drive copy <file-id> --name "Quarterly Report Copy"
# Move a file into a folder, or rename it.
graham drive move <file-id> --to <folder-id>
graham drive rename <file-id> "New Name"
# Star a file (mark it a favorite), or unstar it with --off.
graham drive star <file-id>
graham drive star <file-id> --off
# Move a file to trash (reversible in Drive), restore it, or permanently delete.
graham drive trash <file-id>
graham drive untrash <file-id>
graham drive delete <file-id> --force

graham sheets get <spreadsheet-id>
graham sheets values <spreadsheet-id> "Sheet1!A1:C10"
# Read raw (unformatted) values or cell formulas.
graham sheets values <spreadsheet-id> "Sheet1!A1:C10" --raw
graham sheets values <spreadsheet-id> "Sheet1!A1:C10" --formulas
# Read several ranges at once (batchGet); each block is headed by '# <range>'.
graham sheets values <spreadsheet-id> "Sheet1!A1:B2" "Sheet2!A1:B2"
# Write rows. --row splits on commas (no escaping); --json-rows and --tsv keep
# commas inside a cell, so a `values | set` round trip works.
graham sheets set <spreadsheet-id> "Sheet1!A1:B3" --row "Label,Value" --row "A,10" --row "B,20"
graham sheets set <spreadsheet-id> "Sheet1!A1:B2" --json-rows '[["Label","Value"],["A, B","10"]]'
graham sheets values <spreadsheet-id> "Sheet1!A1:B3" | graham sheets set <spreadsheet-id> "Sheet2!A1:B3" --tsv
# Append rows after the table found within a range (no next-free-row math).
graham sheets append <spreadsheet-id> "Sheet1!A1" --row "C,30" --row "D,40"
# Clear a range's values, leaving formatting intact.
graham sheets clear <spreadsheet-id> "Sheet1!A1:B10"
# Manage tabs: add one (printing its numeric sheet id), rename it, or delete it.
# Positions are one-based; select an existing tab by --sheet-id or --sheet <title>.
graham sheets tab add <spreadsheet-id> "Q3" --index 2
graham sheets tab rename <spreadsheet-id> --sheet "Q3" --to "Q3 2026"
graham sheets tab delete <spreadsheet-id> --sheet-id 1234567
# Freeze rows and/or columns; omit the selector to target the first sheet.
graham sheets freeze <spreadsheet-id> --rows 1 --columns 1
# Resize rows or columns to a pixel size (--from/--to are one-based inclusive).
graham sheets resize <spreadsheet-id> --dimension columns --from 1 --to 3 --pixels 120
# Format a range: bold, a hex background, a number pattern, and/or alignment.
# Colors write the non-deprecated *ColorStyle. --no-bold turns bold off; the
# --clear-* flags reset an aspect; --number-type picks DATE/CURRENCY/PERCENT/...
graham sheets format <spreadsheet-id> "Sheet1!A1:B1" --bold --background "#FFF2CC" --align center
graham sheets format <spreadsheet-id> "Sheet1!B2:B10" --number-format "#,##0.00" --number-type currency
graham sheets format <spreadsheet-id> "Sheet1!A1:B1" --text-color "#202124" --font Roboto --font-size 12
graham sheets format <spreadsheet-id> "Sheet1!A1:B1" --no-bold --clear-background
# Draw cell borders: any of --all/--top/--bottom/--left/--right/--inner, one style.
graham sheets border <spreadsheet-id> "Sheet1!A1:B4" --all --style solid_thick --color "#000000"
# Merge or unmerge cells (--type merge_all|merge_columns|merge_rows).
graham sheets merge <spreadsheet-id> "Sheet1!A1:C1" --type merge_columns
graham sheets unmerge <spreadsheet-id> "Sheet1!A1:C1"
# Sort a range by one or more one-based columns (append :asc or :desc).
graham sheets sort <spreadsheet-id> "Sheet1!A2:D20" --by 2:desc --by 1
# Auto-size rows or columns to their content (one-based; omit the selector for the first sheet).
graham sheets autoresize <spreadsheet-id> --dimension columns --from 1 --to 3
# Name a range, list the named ranges, or delete one by id.
graham sheets named-range add <spreadsheet-id> "Totals" "Sheet1!A1:B10"
graham sheets named-range list <spreadsheet-id>
graham sheets named-range delete <spreadsheet-id> --named-range-id abc123
# Highlight cells that match a condition, or delete a rule by its zero-based index.
graham sheets conditional-format add <spreadsheet-id> "Sheet1!A2:A100" --type NUMBER_GREATER --value 10 --background "#FFCC00"
# Or a gradient (color-scale) rule: min and max stops are required, the mid stop
# optional. A stop type is MIN/MAX (no value) or NUMBER/PERCENT/PERCENTILE (needs
# a value); min defaults to MIN, max to MAX, so a two-color scale needs only colors.
graham sheets conditional-format add <spreadsheet-id> "Sheet1!A1:A100" --gradient --min-color "#FFFFFF" --mid-color "#FFFF00" --mid-type PERCENT --mid-value 50 --max-color "#FF0000"
graham sheets conditional-format delete <spreadsheet-id> --index 0 --sheet "Sheet1"
# Restrict cell input, optionally with an in-cell dropdown; clear it again.
graham sheets validation set <spreadsheet-id> "Sheet1!B2:B100" --type ONE_OF_LIST --value yes --value no --dropdown
graham sheets validation clear <spreadsheet-id> "Sheet1!B2:B100"
# Turn on a basic filter over a range, add a saved filter view, or clear the filter.
graham sheets filter set <spreadsheet-id> "Sheet1!A1:D100"
graham sheets filter-view add <spreadsheet-id> "Sheet1!A1:D100" --title "High priority"
graham sheets filter clear <spreadsheet-id> --sheet "Sheet1"
# Protect a range (prints its id); --warning-only warns instead of blocking edits.
graham sheets protect add <spreadsheet-id> "Sheet1!A1:D10" --description "Locked"
graham sheets protect delete <spreadsheet-id> --protected-range-id 42
# Add a chart and print the chart id; pass it to `slides create chart --chart-id`.
# --kind selects: column/bar/line/area/scatter/combo/pie/histogram/scorecard/candlestick.
graham sheets chart add <spreadsheet-id> --range "Sheet1!A1:B3" --title "Sales" --type column
graham sheets chart add <spreadsheet-id> --range "Sheet1!A1:E20" --kind candlestick
# A pie chart, or an overlay chart floated over a sheet at an anchor cell.
graham sheets chart add <spreadsheet-id> --range "Sheet1!A1:B7" --pie
graham sheets chart add <spreadsheet-id> --range "Sheet1!A1:B7" --anchor "Sheet1!D2" --width 400 --height 300
# Replace a chart's spec, move it to an anchor or its own sheet, or delete it.
graham sheets chart update <spreadsheet-id> --chart-id 12345 --range "Sheet1!A1:C7" --type line
graham sheets chart move <spreadsheet-id> --chart-id 12345 --anchor "Sheet2!D2" --width 300 --height 200
graham sheets chart delete <spreadsheet-id> --chart-id 12345
# Exercise the live Sheets API surface (a value write and read-back, metadata,
# and a chart add) inside the root-level "graham test" folder. The spreadsheet
# is trashed afterward; --keep retains it. Any failed step exits nonzero.
graham sheets test
graham sheets test --keep --folder "graham test"

# Create a new, blank document with `graham drive create doc` (above); every
# create path lives under `drive`. Then work with the document by its id.
graham docs cat <document-id>
# Render the document as GitHub-flavored Markdown: headings, bold/italic/strike,
# links, ordered and unordered nested lists, pipe tables, horizontal rules,
# page-break markers, footnotes, and inline images. --markdown and --json are
# mutually exclusive.
graham docs cat <document-id> --markdown
# List the document's blocks with their zero-based UTF-16 index ranges, kind
# (paragraph, heading, list item, table, section break, TOC), style, list id and
# nesting, object ids, and a text preview. The indices are what the write
# commands below consume; JSON adds the full detail.
graham docs structure <document-id>
graham docs structure <document-id> --format json
# Edit document text (indices are zero-based UTF-16 code units, as the Docs API defines them).
graham docs insert <document-id> --text "Hello" --at 1
graham docs delete <document-id> --from 1 --to 6
# Replace all matches and print how many were changed (case-insensitive unless --match-case).
graham docs replace <document-id> --find "old" --replace "new" --match-case
# Write into a header, footer, or footnote segment (its content starts at index 0),
# or append to the end of the body or a segment with --end (no index needed).
graham docs insert <document-id> --text "Hello" --segment <segment-id> --at 0
graham docs insert <document-id> --text "Hello" --end
graham docs delete <document-id> --from 0 --to 6 --segment <segment-id>
# Style a range of text: --bold/--italic/--underline/--strike/--small-caps are
# toggles (use the --no- form to turn one off), colors are hex like #FF0000, --size
# is in points, --baseline is super/sub/none, and --link sets a URL. At least one
# flag is required.
graham docs style <document-id> --from 1 --to 6 --bold --small-caps --color "#1155CC"
# Style whole paragraphs a range touches: --style is a named style (normal-text,
# title, subtitle, heading-1..heading-6), --align is start/center/end/justified,
# --direction is ltr/rtl, --line-spacing is a percent (100 = single), and spacing
# and indents are in points. --keep-lines-together/--keep-with-next/--avoid-widows/
# --page-break-before are pagination toggles, --shading is a hex background color,
# and --spacing-mode is never-collapse/collapse-lists. --border sets the four outer
# borders and --border-between the between-paragraph border (both hex colors);
# --border-width (points; 0 hides), --border-dash (solid/dot/dash), and
# --border-padding (points) are shared and need a border color. At least one flag
# is required.
graham docs paragraph <document-id> --from 1 --to 20 --style heading-1 --align center
graham docs paragraph <document-id> --from 1 --to 20 --border "#000000" --border-width 1 --border-dash solid
# Shortcut for just the named style: a level 1-6, or title, subtitle, or normal.
graham docs heading <document-id> 2 --from 1 --to 20
# Turn the paragraphs a range touches into a bulleted or numbered list. --preset
# names the glyphs or numbering (disc-circle-square, checkbox, decimal-alpha-roman,
# ...; run `docs bullets --help` for the full list). Nesting comes from leading tabs.
graham docs bullets <document-id> --from 1 --to 20 --preset disc-circle-square
# Remove the bullets from the paragraphs a range touches (nesting is kept as indents).
graham docs unbullet <document-id> --from 1 --to 20
# Edit table structure. A table is located by its zero-based start index (from
# `docs structure`); cell --row/--column are one-based. `create` prints the new
# table's start index (the API inserts a newline, so it is --at + 1).
graham docs table create <document-id> --rows 3 --columns 4 --at 1
graham docs table create <document-id> --rows 3 --columns 4 --end
graham docs table add-row <document-id> --table 5 --row 1 --column 1 --below
graham docs table add-column <document-id> --table 5 --row 1 --column 1 --right
graham docs table delete-row <document-id> --table 5 --row 2 --column 1
graham docs table delete-column <document-id> --table 5 --row 1 --column 2
# Merge/unmerge a rectangular range from a head cell across one-based spans.
graham docs table merge <document-id> --table 5 --row 1 --column 1 --row-span 1 --column-span 2
graham docs table unmerge <document-id> --table 5 --row 1 --column 1 --row-span 1 --column-span 2
# Pin the first N rows as headers; 0 unpins.
graham docs table pin-headers <document-id> --table 5 --count 1
# Style a cell range (give --row/--column, one-based, with optional --row-span/
# --column-span) or the whole table (omit them). --border sets all four cell
# borders and needs a color (width defaults to 1pt, dash to solid); --padding sets
# all four paddings; --align is top/middle/bottom. At least one style is required.
graham docs table style <document-id> --table 5 --row 1 --column 1 --background "#F1F3F4" --align middle
graham docs table style <document-id> --table 5 --border "#000000" --border-width 1 --border-dash solid
# Set row height/overflow for listed one-based --rows (omit for every row). To
# mark header rows, use `pin-headers`; the Docs API cannot set a header row via
# row style.
graham docs table row-style <document-id> --table 5 --rows 1 --min-height 24 --prevent-overflow
# Set the width of listed one-based --columns (omit for every column): a fixed
# --width in points (>= 5) or --evenly distributed. Exactly one of the two.
graham docs table column-width <document-id> --table 5 --columns 1 2 --width 90
graham docs table column-width <document-id> --table 5 --evenly
# Any write can require the document be at a known revision (optimistic concurrency);
# the write fails instead of overwriting a concurrent edit.
graham docs insert <document-id> --text "Hello" --at 1 --require-revision <revision-id>
# List every inline and positioned image (origin, object id, size, source and
# content URIs), or download them under safe deterministic names.
graham docs images <document-id>
graham docs images <document-id> --download ./images
# Insert a page break (body only) at a zero-based index, or at the end of the body.
graham docs page-break <document-id> --at 5
graham docs page-break <document-id> --end
# Insert an inline image from a public URI (PNG/JPEG/GIF, < 50MB, <= 25 megapixels;
# Google fetches it once at insertion time). --width/--height are optional points.
# The new image's object id is printed. --segment targets a header or footer.
graham docs image insert <document-id> --uri https://example.com/pic.png --at 5 --width 120 --height 80
graham docs image insert <document-id> --uri https://example.com/pic.png --end
# Replace an existing image in place (object id from `docs images`); the only
# method is center-crop (scale and center to fill the original bounds).
graham docs image replace <document-id> <image-object-id> --uri https://example.com/new.png
# Insert a continuous or next-page section break (body only) at an index or the end.
graham docs section-break <document-id> --type continuous --at 3
graham docs section-break <document-id> --type next-page --end
# Create a header or footer (DEFAULT type) and print its new segment id; pass the
# id to `docs insert --segment <id>` to fill it. --at scopes it to a section.
graham docs header create <document-id>
graham docs footer create <document-id> --at 3
# Delete a header or footer by its segment id.
graham docs header delete <document-id> <header-id>
graham docs footer delete <document-id> <footer-id>
# Create a footnote (its reference goes in the body) and print the new footnote
# segment id. With --text, the text is inserted into the footnote segment (a second
# write, since the id is only known after the reference is created).
graham docs footnote <document-id> --at 5
graham docs footnote <document-id> --end --text "See the appendix."
# Name a zero-based UTF-16 range (name 1-256 units, need not be unique) and print
# its new id; later `fill` it to replace its content (the template-filling primitive).
graham docs range create <document-id> --name greeting --from 2 --to 8
# List the document's existing named ranges (id, name, and index spans) so their
# ids and names can be used with delete/fill. --format json adds segment/tab ids.
graham docs range list <document-id>
graham docs range list <document-id> --format json
# Delete a named range by id, or every range sharing a name (exactly one selector).
graham docs range delete <document-id> --id <named-range-id>
graham docs range delete <document-id> --name greeting
# Replace a named range's content by id or name; --text may be empty to clear it.
graham docs range fill <document-id> --id <named-range-id> --text "Hello, world"
graham docs range fill <document-id> --name greeting --text "Hi"
# Set document-wide page style. --page-width/--page-height are a pair (both or
# neither, in points); margins are in points; --background is a hex color;
# --mode is pages or pageless. --page-number-start sets the first page number;
# --margin-header/--margin-footer set the header/footer margins (each turns on
# custom header/footer margins); --flip-orientation swaps width and height.
graham docs page-setup <document-id> --page-width 612 --page-height 792
graham docs page-setup <document-id> --margin-top 72 --margin-bottom 72 --margin-left 90 --margin-right 90
graham docs page-setup <document-id> --first-page-header-footer --background "#FFFFFF"
graham docs page-setup <document-id> --margin-header 24 --margin-footer 24 --page-number-start 1
graham docs page-setup <document-id> --mode pageless --flip-orientation
# Set the style of the sections a body range overlaps: margins (points), the
# first page number (--page-number-start), --direction ltr/rtl, --column-separator
# none/between, --first-page-header-footer, and --flip-orientation. Indices are
# zero-based UTF-16; the section's header/footer ids and type are read-only, and
# multi-column layout is not set here. At least one option is required.
graham docs section-style <document-id> --from 1 --to 20 --margin-left 108 --margin-right 108
graham docs section-style <document-id> --from 1 --to 20 --column-separator between --page-number-start 1
# Exercise the complete live Docs API surface inside the root-level "graham test" folder.
# The run creates a disposable document and exercises text, styling, lists, tables,
# images, headers/footers/footnotes, named ranges, and page setup.
# The created document is trashed afterward; --keep retains it. Any failed step exits nonzero.
graham docs test
graham docs test --keep --folder "graham test" --image-url https://example.com/image.png

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
# List the deck's exact layout ids, or add a slide using one.
graham slides layouts <presentation-id>
graham slides add <presentation-id> --layout-id <layout-id>
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
graham slides element transform <presentation-id> <object-id> --translate-x 10 --unit pt
graham slides element reorder <presentation-id> <object-id> --to front
# Delete any page element by exact id (deleting a group deletes its children too).
graham slides element delete <presentation-id> <object-id>
# Set or clear either alt-text field; clearing both removes the element's alt text.
graham slides alt-text <presentation-id> <object-id> --title "Chart" --description "Quarterly revenue"
graham slides alt-text <presentation-id> <object-id> --clear-title --clear-description
# Read, set, or clear presenter speaker notes by slide id.
graham slides notes show <presentation-id>
graham slides notes set <presentation-id> <slide-id> --text "Discuss the forecast"
graham slides notes clear <presentation-id> <slide-id>
# Style a shape's fill, outline, and drop shadow (colors are hex like #FF0000 or theme names like accent1).
graham slides style shape <presentation-id> <object-id> --fill "#FFCC00" --outline accent1 --outline-weight 2
graham slides style shape <presentation-id> <object-id> --no-fill --shadow-color "#000000" --shadow-blur 4 --align middle
# Style an image's outline (brightness, contrast, transparency, crop, recolor, and shadow are read-only in the Slides API).
graham slides style image <presentation-id> <object-id> --outline "#333333" --outline-weight 1
# Style a line's color, weight, dash, and arrow ends.
graham slides style line <presentation-id> <object-id> --color accent2 --weight 3 --dash dash-dot --end-arrow open-arrow
# Style a video's playback and outline.
graham slides style video <presentation-id> <object-id> --autoplay --mute --start 5 --end 30
# Edit table structure with one-based row and column indices.
graham slides table insert-rows <presentation-id> <table-id> --below 2 --count 2
graham slides table insert-columns <presentation-id> <table-id> --right-of 1
graham slides table merge <presentation-id> <table-id> --row 1 --column 1 --row-span 2 --column-span 3
# Style cells, dimensions, and borders; omit a range to update the whole table.
graham slides table style-cells <presentation-id> <table-id> --fill accent1 --align middle
graham slides table row-height <presentation-id> <table-id> --min-height 24 --rows 1 3
graham slides table column-width <presentation-id> <table-id> --width 72
graham slides table borders <presentation-id> <table-id> --position inner-horizontal --weight 1 --dash solid
# Edit the text in a shape or table cell (text ranges are zero-based; --row/--column are one-based).
graham slides text insert <presentation-id> <object-id> --text "Hello" --at 0
graham slides text delete <presentation-id> <object-id> --from 0 --to 5
# Style a text run's weight, color, font, size, baseline, and link.
graham slides text style <presentation-id> <object-id> --bold --color "#FF0000" --link https://example.com
# Style paragraphs: alignment, line spacing, spacing, indents, and direction.
graham slides text paragraph <presentation-id> <object-id> --align center --line-spacing 150
# Add or remove list bullets over a range (omit the range to cover the whole text).
graham slides text bullets <presentation-id> <object-id> --preset disc-circle-square
graham slides text unbullet <presentation-id> <object-id>
# Refresh a linked Sheets chart embedded on a slide.
graham slides chart refresh <presentation-id> <object-id>
# Move one slide to a one-based final position (as shown by cat and list).
graham slides move <presentation-id> <slide-id> --to 1
# Delete one slide by its exact object id.
graham slides delete <presentation-id> <slide-id>
# Exercise the complete live API surface inside the root-level "graham test" folder.
# The run builds a live Sheets chart and embeds it linked in the test deck.
# Created files are trashed afterward; --keep retains them. Any failed step exits nonzero.
graham slides test
graham slides test --keep --folder "graham test" --image-url https://example.com/image.png
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
