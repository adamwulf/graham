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

- **`addDocumentTab` / `deleteTab` / `updateDocumentTabProperties`** — built as
  `docs tab add|delete|update` (add prints the new tab id from the reply;
  positions are one-based and translated to the API's zero-based `index`;
  `--parent` nests a tab). The read-only `nestingLevel` is out by design.
- **Tab-aware reads** — built: `document(id:includeTabsContent:)` populates a
  `DocTab`/`DocTabContent` tree, `docs tab list` flattens it, and `docs structure
  --tab <id>` / `docs cat --tab <id>` read one tab's blocks or text. Deferred:
  per-tab Markdown (`docs cat --markdown --tab`), per-tab headers/footers/images,
  and the `suggestionsViewMode` get parameter (part of the suggestions work).
- **Write-side `tabId` / `tabsCriteria` threading** — the core is done:
  `--tab-id` on `docs insert` and `docs delete` (on the location/range) and
  `--tab-id` (repeatable) on `docs replace` (a `tabsCriteria`), plus the
  `--tab-id` already on `docs named-style`, the smart chips, and the tab writes.
  Deferred (low value, mechanical when needed — the models already carry the
  field): `--tab-id` on the styling and table ops, and `tabsCriteria` on the
  named-range operations.
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
