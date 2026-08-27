# Roadmap

Not-yet-done work only. For completed features and commands, see `README.md`.
For architecture and implementation conventions, see `CLAUDE.md`.

**Google Docs is at practical 100%** — every `core` and `useful` operation is
built and merged. Only the explicitly-deferred advanced items below remain.
**Google Sheets is complete** — the ranked build-out (values, tabs, grid
shape, formatting, charts) and the advanced polish (the full formatting surface,
structure, data tooling, every chart type, and both boolean and gradient
color-scale conditional formatting) are all built. No Sheets items remain.

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

- **`updateSectionStyle`** — built as `docs section-style` (margins, page
  numbering, direction, column separator, first-page header/footer flag, flip
  orientation). One sub-item is deferred: the per-column `columnProperties`
  layout (multi-column width / padding), which is awkward from a CLI; the
  section's header/footer ids and `sectionType` are read-only and out by design.
- **`updateNamedStyle`** — built as `docs named-style` (redefines a named style
  document-wide with the `docs style` text flags and the `docs paragraph`
  alignment / spacing / indent flags; `--tab-id` scopes it to a tab). The
  baseline offset and link (nonsensical for a style definition) and the
  pagination toggles, shading, and borders are out by design.

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
- **`insertPerson` / `insertRichLink` / `insertDate`** — built as
  `docs chip person|rich-link|date` (each inserts at a zero-based `--at` index or
  the segment end `--end`, with `--segment` and `--tab-id`). The date chip's
  `DATE_FORMAT_CUSTOM` (no pattern field) and the read-only `displayText` are out.
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

## Sheets — done

The full Sheets build-out is complete; no items remain. See `README.md` for the
command surface and `CLAUDE.md` for the write-endpoint recipe and index
conventions. Both conditional-format paths ship: boolean rules (`sheets
conditional-format add --type … --background …`) and gradient color-scale rules
(`sheets conditional-format add --gradient --min-color … --max-color …`).
