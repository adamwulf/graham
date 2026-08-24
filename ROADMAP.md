# Roadmap

What is still to do. For completed features and commands, see `README.md`. For
architecture and implementation conventions, see `CLAUDE.md`.

The remaining focus is comprehensive Google Slides write support. Slides
writes use `presentations.batchUpdate` with typed request bodies. File
creation, the complete nine-type page-element model, detailed element reading,
and image listing/download are complete.

## Next milestone: slide lifecycle and batch-update foundation

Build the shared write path first, then use it for a complete slide-structure
workflow. This gives later element-editing commands one tested batch-update
foundation instead of independently constructing requests.

### API and library

- Add typed `presentations.batchUpdate` request, request-union, reply, and
  response models under `Models/`. Request fields should be required where the
  API operation requires them; response fields should decode defensively.
- Add a `SlidesClient` batch-update executor for
  `POST /v1/presentations/{presentationId}:batchUpdate`. The client owns URL
  construction and response decoding; the CLI must not construct JSON.
- Add high-level client methods for `createSlide`, `updateSlidesPosition`, and
  `deleteObject`. Escape presentation IDs with
  `GoogleURL.escapePathComponent`.
- `updateSlidesPosition.insertionIndex` is based on the order before the move.
  A high-level `moveSlide` method must resolve the current slide index and
  translate the requested final position correctly, especially when moving a
  slide forward. Do not implement this as `position - 1` alone.
- Keep the generic batch-update representation extensible so later element,
  geometry, text, and appearance requests can join the same request union.

### CLI

- `graham slides add <presentation-id> [--at <position>] [--layout <layout>]`
  creates a slide. Default to appending a `BLANK` slide and print the new slide
  object ID.
- `graham slides move <presentation-id> <slide-id> --to <position>` reorders one
  slide to the requested final position and prints its ID.
- `graham slides delete <presentation-id> <slide-id>` deletes one exact slide
  ID and prints that ID. It must never infer or expand the target.
- User-facing positions are one-based, matching `slides cat` and `slides list`;
  translate them to the API semantics in `GrahamKit`.
- Keep commands thin: parse arguments, call `SlidesClient`, and print the
  result.

### Completion criteria

- Static `StubTransport` tests assert the exact POST method, escaped path, JSON
  body, and decoded replies for add, move, and delete. Include insertion at the
  beginning, append behavior, predefined-layout encoding, and empty replies.
- Move tests cover forward, backward, no-op, first/last, missing-ID, and
  out-of-range cases, including the extra presentation read needed to resolve
  the API insertion index.
- CLI parsing tests cover defaults, positive one-based position validation,
  required IDs, layout parsing, and all three registered subcommands.
- Existing `slides cat`, `slides list`, and `slides images` behavior remains
  unchanged.
- No test calls Google or any other live network service. The full `swift test`
  suite passes.
- README usage and this roadmap move the milestone to completed only after
  implementation and review.

## Slides: create elements

Add every element type that the Slides batch-update API can create:

- **Shape / text box** (`createShape`), **image** (`createImage`), **video**
  (`createVideo`, from YouTube or Drive), **line / connector** (`createLine`),
  **table** (`createTable`), and **chart from Sheets** (`createSheetsChart`).
- **Group / ungroup** elements (`groupObjects`, `ungroupObjects`).
- Start with a vertical slice that creates a text box and inserts text,
  returning every new object ID needed by later edits.

## Slides: edit geometry

- **Move, resize, scale, and rotate** any element
  (`updatePageElementTransform`).
- **Reorder** elements front-to-back (`updatePageElementsZOrder`).
- Handle grouped-element coordinate spaces deliberately; a child transform is
  relative to its group.

## Slides: edit appearance

- **Image recolor and adjustments** (`updateImageProperties`): opacity,
  brightness, contrast, crop, outline, and drop shadow.
- **Other element styles:** shape fill, outline, and drop shadow
  (`updateShapeProperties`); line properties (`updateLineProperties`); video
  properties (`updateVideoProperties`).
- **Tables:** insert/delete rows and columns, merge/unmerge cells, and edit
  cell, row, column, and border properties (the `*Table*` requests).
- **Charts:** refresh a linked Sheets chart (`refreshSheetsChart`).

## Slides: edit text and links

- **Text blocks:** insert/delete text and style runs and paragraphs
  (`insertText`, `deleteText`, `updateTextStyle`, `updateParagraphStyle`).
- **Bullets / lists:** add/remove list formatting (`createParagraphBullets`,
  `deleteParagraphBullets`).
- **Links:** set or clear a text-run link through `updateTextStyle`.

## Slides: alt text

- **Add, edit, or clear alt text** on any page element through
  `updatePageElementAltText`. Clearing both `title` and `description` is the API
  equivalent of deleting alt text.

## Slides: presenter notes

- **Add, update, or delete presenter notes** by editing the notes-page text
  through `presentations.batchUpdate`.

## Slides: delete objects and files

- Extend the exact-ID delete operation from slides to any page element
  (`deleteObject`).
- Delete the entire presentation through Drive `files.delete`, or add a
  deliberate trash operation.

## Suggested order

1. **Slide lifecycle and shared batch-update foundation** — the next milestone defined above.
2. **Create elements**, beginning with a text box plus inserted text.
3. **Geometry**, then **appearance**.
4. **Text and links**, **alt text**, and **presenter notes**.
5. **General element deletion** and whole-presentation deletion or trash.
