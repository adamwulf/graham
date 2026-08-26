# Roadmap

Not-yet-done work only. For completed features and commands, see `README.md`.
For architecture and implementation conventions, see `CLAUDE.md`.

**Google Docs is at practical 100%** — every `core` and `useful` operation is
built and merged. Only the explicitly-deferred advanced items below remain.
**Sheets** is the next major area (see the end of this file).

---

## Docs — deferred (advanced) items only

Basis: the live Docs v1 discovery document (revision `20260819`). All the
`core` and `useful` phases are done — reads (full model, `docs structure`,
`docs cat --markdown`, `docs images`), text/paragraph styling, lists, complete
table structure and styling, structure and images, headers/footers/footnotes,
and named ranges plus document style. Only the advanced items below remain, and
they are rarely needed from a CLI.

Every remaining write item follows the CLAUDE.md write recipe: a typed
`Docs*Request` case in `Models/DocsBatchUpdateModels.swift`, a high-level method
in `APIs/DocsClient.swift`, offline `StubTransport` tests (exact method, URL,
encoded body, decoded reply, error propagation), then a thin subcommand in
`Commands/DocsCommand.swift`.

### Index rules (apply to every operation)

- Docs text indices stay **zero-based** (UTF-16 code units), matching the API
  and the existing convention. The body guard `index >= 1` is body-only:
  header, footer, and footnote segments start their content at index 0, so
  segment-aware methods must not reuse the body guard.
- Docs table rows, columns, and tab positions are **zero-based in the API**
  (`TableCellLocation.rowIndex/columnIndex`, `rowIndices`, `columnIndices`,
  `TabProperties.index`). The CLI shows and accepts **one-based** values;
  GrahamKit translates.

### Section and named styles (advanced)

- **`updateSectionStyle`** *(advanced)* — margins, columns, page numbering, and
  header/footer ids for the sections overlapping a range; `fields` mask; the
  range's `segmentId` must be empty. CLI `docs section-style`.
- **`updateNamedStyle`** *(advanced)* — redefine a named style (e.g. what
  `HEADING_2` looks like document-wide); the mask must include
  `named_style_type`. CLI `docs named-style`.

### Tabs, smart chips, suggestions (advanced, beyond the cut line)

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

### Practical "100%" reached

Every `core` and `useful` operation is built, including paragraph borders and
the `docs range list` convenience: document creation, full text and paragraph
styling, lists, complete table structure and styling, structure and images,
page breaks, section breaks, headers/footers/footnotes, named ranges (template
filling and listing), page setup (including pageless), and structured/Markdown
reads. What is left above — `updateSectionStyle`, `updateNamedStyle`, and the
tabs / smart-chips / suggestions group — is advanced polish, rarely needed from
a CLI. The read-only `ParagraphStyle.tabStops` and `TextStyle`/`DocumentStyle`
ids are not writable and are intentionally omitted.

### Notes for implementation

- The Response union defines 8 reply shapes; one of them,
  `insertInlineSheetsChartResponse`, has **no matching request** — charts cannot
  be inserted into Docs via the API. Decode it defensively; do not plan a write
  for it.
- Every operation runs under the scopes graham already requests (`documents`
  or `drive`); no `GoogleScope` change is needed.

---

## Sheets — the active build-out

This is the next major area. Docs is at practical 100%, so work now moves here.

### What is built today

`SheetsClient.swift` holds: `spreadsheet` (get metadata, including frozen row /
column counts), `values` (read a range, with a `valueRenderOption`),
`batchGetValues` (multi-range read), `setValues` (write a range, `USER_ENTERED`),
`appendValues` (append rows after a table), `clearValues` (clear a range),
`batchUpdate` (the shared batch-write path), `addChart` (a basic chart on its own
new sheet), and the tab operations `addSheet` / `deleteSheet` / `renameSheet`
(plus `sheetId(title:)` resolution). The CLI exposes these as `sheets get`,
`sheets values` (`--raw` / `--formulas`, one or more ranges), `sheets set`
(`--row` / `--json-rows` / `--tsv`), `sheets append`, `sheets clear`,
`sheets tab add` / `delete` / `rename`, and `sheets chart add`.

`graham sheets test` runs the live end-to-end Sheets smoke test over that surface
(`SheetsLiveTest.swift`), with real value write / append / clear
read-back round-trips. It is the Sheets analog of `graham docs test` and
`graham slides test`; the Slides test keeps only a minimal chart-source
spreadsheet, so each test exercises its own service.

### How each item ships

Every item is one unit of work in the repo pattern:

1. Typed request/response models under `Models/` (a new `SheetsBatchUpdateRequest`
   case where the operation is a batch write).
2. A high-level `SheetsClient` method that owns the endpoint, escaped path, HTTP
   method, and body.
3. Offline `StubTransport` tests (exact method, URL, encoded body, decoded
   reply, empty reply, and Google-error propagation).
4. A thin CLI subcommand.
5. **Grow `sheets test`** to cover the new operation, with a read-back where
   practical — the live surface test must keep pace with the client surface.

Index conventions (apply throughout): A1 ranges parse through `A1Range.parse`
(never hand-build a `GridRange`). `SheetProperties.index`, dimension ranges, and
grid indices are zero-based (dimension ranges are also half-open); the CLI shows
and accepts one-based (inclusive for dimensions) and `GrahamKit` translates.
Building a fields mask reuses the Slides `update*Properties` mask convention.

### Phase 3 — Grid shape

- **Freeze** — `updateSheetProperties.gridProperties`
  (`frozenRowCount` / `frozenColumnCount`). The read side (surfacing the counts
  in `sheets get`) is already built; only the write remains.
- **Resize** — `updateDimensionProperties` for row height / column width.
  Dimension ranges are zero-based half-open; the CLI is one-based inclusive.
- Grow `sheets test`: freeze the header row and read it back through `get`;
  resize a column.

### Phase 4 — Cell formatting

- **First formatting slice** — `repeatCell` with a small `CellFormat`:
  `sheets format <range> --bold --background <color> --number-format <pattern>
  --align <h>`. `A1Range.parse` already yields the `GridRange`.
- Grow `sheets test`: format the header row.

### Phase 5 — Chart upgrades

- One unit each: overlay position with an anchor cell and pixel size; a
  `pieChart` spec plus the `COMBO` type; `deleteEmbeddedObject` +
  `updateChartSpec`; and listing `sheets.charts` in `sheets get` so charts are
  listable.
- Grow `sheets test`: add an overlay chart, list it through `get`, then update
  and delete it.
