# Roadmap

Not-yet-done work only. For completed features and commands, see `README.md`.
For architecture and implementation conventions, see `CLAUDE.md`.

The current focus is finishing **Google Docs** to practical 100%. Sheets work is
deferred until Docs is done (see the end of this file).

---

## Docs — remaining work

Basis: the live Docs v1 discovery document (revision `20260819`). The
`documents.batchUpdate` Request union holds **40 operations**; graham implements
3 (`insertText`, `deleteContentRange`, `replaceAllText`), so **37 remain**.
Phase 1 (foundations) and Phase 2 (richer reads) are done: `documents.create`,
`WriteControl`, segment-aware text edits, the shared write models, the full
read model, the `Document.blockRows` facade (`docs structure`), `docs cat
--markdown`, and `docs images`. What remains is the write surface — text and
paragraph styling, lists, tables, structure and images, headers/footers/
footnotes, and named ranges and document style.

Every write item follows the CLAUDE.md write recipe: a typed `Docs*Request` case
in `Models/DocsBatchUpdateModels.swift`, a high-level method in
`APIs/DocsClient.swift`, offline `StubTransport` tests (exact method, URL,
encoded body, decoded reply, error propagation), then a thin subcommand in
`Commands/DocsCommand.swift`. Only item-specific work is listed below.

### Index rules (apply to every phase)

- Docs text indices stay **zero-based** (UTF-16 code units), matching the API
  and the existing convention. The body guard `index >= 1` is body-only:
  header, footer, and footnote segments start their content at index 0, so
  segment-aware methods must not reuse the body guard.
- Docs table rows, columns, and tab positions are **zero-based in the API**
  (`TableCellLocation.rowIndex/columnIndex`, `rowIndices`, `columnIndices`,
  `TabProperties.index`). The CLI shows and accepts **one-based** values;
  GrahamKit translates.

### Phase 3 — Paragraph borders (deferred sub-item)

`updateTextStyle` and `updateParagraphStyle` are done (`docs style`,
`docs paragraph`, `docs heading`), covering fonts, colors, links, alignment,
spacing, indents, and named styles. Only paragraph **borders** remain from the
`updateParagraphStyle` surface — a larger sub-model deliberately split out to
keep the styling change reviewable:

- **Paragraph borders** *(useful)* — `borderTop`, `borderBottom`, `borderLeft`,
  `borderRight`, `borderBetween`, each a `ParagraphBorder` (color, width,
  dashStyle, padding). Extend `DocsParagraphStyle` and its mask; add
  `docs paragraph` border flags. Same fields-mask discipline and exact-string
  tests.

### Phase 4 — Lists (next up)

- **`createParagraphBullets`** *(core)* — turn the paragraphs overlapping a range
  into a list using a `bulletPreset` (16 presets, e.g.
  `BULLET_DISC_CIRCLE_SQUARE`, `BULLET_CHECKBOX`,
  `NUMBERED_DECIMAL_ALPHA_ROMAN`). Nesting comes from leading tab characters.
  Request case + preset enum; CLI `docs bullets <id> --from --to --preset`.
  Zero-based UTF-16 range.
- **`deleteParagraphBullets`** *(core)* — remove bullets from paragraphs
  overlapping a range, preserving visual nesting via indents. CLI
  `docs bullets --remove` (or `docs unbullet`). Zero-based UTF-16 range.

### Phase 5 — Tables

All table operations locate the table by its zero-based start index (from
`docs structure`) and address cells through `DocsTableCellLocation`. CLI rows
and columns are one-based; GrahamKit subtracts one. Replies are empty objects.
Add tests in a new `DocsTableWriteTests.swift`, mirroring
`SlidesTableWriteTests.swift`.

- **`insertTable`** *(core)* — insert an empty rows x columns table at an index
  or at the end of a segment. The API inserts a newline first, so the table
  start index is location index + 1 — print the real start index after the
  write. CLI `docs table create`.
- **`insertTableRow`** *(core)* — insert an empty row above or below a reference
  cell. CLI `docs table add-row`.
- **`insertTableColumn`** *(core)* — insert an empty column left or right of a
  reference cell. CLI `docs table add-column`.
- **`deleteTableRow`** *(core)* — delete the row of a reference cell (a merged
  cell deletes every row it spans). CLI `docs table delete-row`.
- **`deleteTableColumn`** *(core)* — delete the column of a reference cell. CLI
  `docs table delete-column`.
- **`updateTableCellStyle`** *(useful)* — style a `DocsTableRange` or a whole
  table (background, borders, padding, alignment); `fields` mask. CLI
  `docs table style`.
- **`updateTableRowStyle`** *(useful)* — row height / header / overflow for
  listed `rowIndices`. CLI `docs table row-style`.
- **`updateTableColumnProperties`** *(useful)* — column width (`FIXED_WIDTH`
  >= 5pt) for listed `columnIndices`. CLI `docs table column-width`.
- **`mergeTableCells`** *(useful)* — merge a `DocsTableRange`; text concatenates
  into the head cell. CLI `docs table merge`.
- **`unmergeTableCells`** *(useful)* — unmerge all merged cells in a range. CLI
  `docs table unmerge`.
- **`pinTableHeaderRows`** *(useful)* — pin the first N rows as headers; 0
  unpins. CLI `docs table pin-headers`.

### Phase 6 — Structure and images

- **`insertPageBreak`** *(core)* — insert a page break plus newline; body only.
  CLI `docs page-break`. Zero-based UTF-16, body index >= 1, or end-of-segment.
- **`insertInlineImage`** *(core)* — insert an image from a URI (<50MB,
  <=25 megapixels, PNG/JPEG/GIF), optional `objectSize`; the reply carries the
  new `objectId`. CLI `docs image insert <id> --uri --at [--width --height]`.
  The URI must be publicly fetchable by Google at insertion time.
- **`replaceImage`** *(useful)* — swap an existing image by object id; the only
  replace method is `CENTER_CROP`. CLI `docs image replace`.
- **`deletePositionedObject`** *(useful)* — delete a positioned object by id
  (positioned objects cannot be created through the API, only deleted or
  restyled). CLI `docs object delete`.
- **`insertSectionBreak`** *(useful)* — insert a `CONTINUOUS` or `NEXT_PAGE`
  section break; body only. CLI `docs section-break`.
- **`updateSectionStyle`** *(advanced)* — margins, columns, page numbering, and
  header/footer ids for the sections overlapping a range; `fields` mask; the
  range's `segmentId` must be empty.

### Phase 7 — Headers, footers, footnotes

Create replies carry the new segment id (`headerId` / `footerId` /
`footnoteId`); print it so follow-up segment writes can target it.

- **`createHeader`** *(useful)* — create a header; the only `type` is `DEFAULT`;
  optional `sectionBreakLocation` scopes it to a section. First-page and
  even-page headers are enabled through `updateDocumentStyle` flags, not here.
  CLI `docs header create`.
- **`createFooter`** *(useful)* — same shape for footers. CLI
  `docs footer create`.
- **`deleteHeader`** *(useful)* — delete a header by `headerId`. CLI
  `docs header delete`.
- **`deleteFooter`** *(useful)* — delete a footer by `footerId`. CLI
  `docs footer delete`.
- **`createFootnote`** *(useful)* — create a footnote segment and insert its
  reference at a body location; the new segment starts with a space and a
  newline. CLI `docs footnote <id> --at [--text]`; with `--text`, batch a
  follow-up `insertText` into the returned `footnoteId` segment (segment content
  starts at index 0, but the auto-inserted space occupies index 0-1, so insert
  at index 1).

### Phase 8 — Named ranges and document style

- **`createNamedRange`** *(useful)* — name a range (name 1-256 UTF-16 units, not
  unique); the reply carries `namedRangeId`. CLI `docs range create`. Zero-based
  UTF-16 range.
- **`deleteNamedRange`** *(useful)* — delete by `namedRangeId` or by `name` (all
  with that name); the two selectors are mutually exclusive — enforce one-of in
  the client. CLI `docs range delete`.
- **`replaceNamedRangeContent`** *(useful)* — replace the content of a named
  range (by id or name) with text; for a discontinuous named range only the
  first subrange is replaced. This is the template-filling primitive. CLI
  `docs range fill`.
- **`updateDocumentStyle`** *(useful)* — page size, margins,
  `useFirstPageHeaderFooter`, `useEvenPageHeaderFooter`, pageless mode,
  background; `fields` mask. CLI `docs page-setup`.
- **`updateNamedStyle`** *(advanced)* — redefine a named style (e.g. what
  `HEADING_2` looks like document-wide); the mask must include
  `named_style_type`. CLI `docs named-style`.

### Phase 9 — Tabs, smart chips, suggestions (advanced, beyond the cut line)

- **`addDocumentTab`** *(advanced)* — add a tab; the reply returns
  `TabProperties`. `TabProperties.index` is zero-based; the CLI shows one-based.
- **`deleteTab`** *(advanced)* — delete a tab and its child tabs.
- **`updateDocumentTabProperties`** *(advanced)* — rename / move a tab; `fields`
  mask.
- **`documents.get` parameters** *(advanced)* — `includeTabsContent` (populate
  `Document.tabs` instead of the legacy top-level fields) and
  `suggestionsViewMode`. Optional parameters on `DocsClient.document(id:)`, a
  `Tab`/`DocumentTab` model, and tab-aware `blockRows`. Also surface
  `tabsCriteria` on `replaceAllText` and the named-range operations, and `tabId`
  on locations, once tabs are modeled.
- **`insertPerson`** *(advanced)* — insert a person smart chip (email required).
- **`insertRichLink`** *(advanced)* — insert a Drive/YouTube/Calendar smart chip
  from a URI.
- **`insertDate`** *(advanced)* — insert a date smart chip (timestamp, locale,
  date and time format enums).
- **Suggestions-aware reads** *(advanced)* — the `suggested*` fields and
  `suggestionsViewMode` render modes; skip until a real need appears.

### Practical "100%" cut line

**Phases 1-8** (all `core` + `useful` items) = practical 100%. That covers
document creation, full text/paragraph styling, lists, complete table editing,
images, breaks, headers/footers/footnotes, named ranges (template filling),
page setup, and structured/Markdown reads. **Phase 9 plus every `advanced`
item** (`updateSectionStyle`, `updateNamedStyle`, tabs, smart chips,
suggestions) is rarely needed from a CLI and can wait indefinitely.

### Notes for implementation

- The Response union defines 8 reply shapes; one of them,
  `insertInlineSheetsChartResponse`, has **no matching request** — charts cannot
  be inserted into Docs via the API. Decode it defensively; do not plan a write
  for it.
- All 40 operations run under the scopes graham already requests (`documents`
  or `drive`); no `GoogleScope` change is needed for any phase.

---

## Sheets — deferred until Docs is complete

Ranked; each item is one unit of work in the repo pattern (typed batch-update
case + high-level client method + offline StubTransport tests + thin CLI
command). See the built Sheets surface in `SheetsClient.swift`.

1. **`values.append` -> `sheets append`** *(quick win)* — add rows without first
   finding the next free row. One endpoint (POST
   `.../values/{range}:append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS`),
   reuses `UpdateValuesRequestBody`, no batch-update case, no index math.
2. **Tab management** — `addSheet` + `deleteSheet` + rename
   (`updateSheetProperties`), as a `sheets tab` group. `SheetProperties.index`
   is zero-based; the CLI accepts one-based and translates. `deleteSheet` takes a
   numeric `sheetId`; resolve a title to its id via `spreadsheet(id:)`.
3. **`values.clear` -> `sheets clear`** — POST `:clear` with an empty body; very
   small, can ride with item 1.
4. **Freeze and resize** — `updateSheetProperties.gridProperties` +
   `updateDimensionProperties`, reusing the Slides fields-mask convention.
   Dimension ranges are zero-based, half-open; the CLI takes one-based inclusive.
5. **First formatting slice** — `repeatCell` with a small `CellFormat`:
   `sheets format <range> --bold --background <color> --number-format <pattern>
   --align <h>`. `A1Range.parse` already yields the `GridRange`.
6. **Chart upgrades** (one unit each) — overlay position with anchor cell and
   pixel size; `pieChart` spec + `COMBO` type; `deleteEmbeddedObject` +
   `updateChartSpec`, plus `sheets.charts` in `sheets get` so charts are
   listable.
7. **Read options + `batchGet`** — `--raw` and `--formulas` on `sheets values`,
   multi-range reads, and `frozenRowCount`/`frozenColumnCount` in `sheets get`.
8. **`sheets set` input escaping** — accept TSV on stdin or a `--json` rows
   argument so cells can contain commas and a `values | set` round trip works.
