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

All `core` + `useful` operations are built: document creation, full text and
paragraph styling, lists, complete table structure and styling, structure and
images, page breaks, section breaks, headers/footers/footnotes, named ranges
(template filling), page setup (including pageless), and structured/Markdown
reads. What is left above — paragraph borders, `updateSectionStyle`,
`updateNamedStyle`, a `docs range list` convenience, and the tabs / smart-chips /
suggestions group — is optional polish, rarely needed from a CLI.

### Notes for implementation

- The Response union defines 8 reply shapes; one of them,
  `insertInlineSheetsChartResponse`, has **no matching request** — charts cannot
  be inserted into Docs via the API. Decode it defensively; do not plan a write
  for it.
- Every operation runs under the scopes graham already requests (`documents`
  or `drive`); no `GoogleScope` change is needed.

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
