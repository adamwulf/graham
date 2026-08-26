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

### Phase 8 — Named ranges and document style (next up — last core+useful phase)

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
