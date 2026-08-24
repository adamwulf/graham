# Roadmap

What is still to do. For what already works, see `README.md`. For the
architecture and the recipes that show how to add each kind of feature, see
`CLAUDE.md`.

The focus is comprehensive Google Slides write support for every page-element
type. Writes are mostly POST `batchUpdate` endpoints with request bodies.
`GoogleAPI.sendJSON(_:method:url:body:)` already exists; add request-body models
under `Models/` as each feature lands. File creation, the complete page-element
model foundation, detailed element reading, and image downloads are complete;
see `README.md` for their commands.

## Slides: create elements

Add each element type to a slide:

- **Shape / text box** (`createShape`), **image** (`createImage`), **video**
  (`createVideo`, from YouTube or Drive), **line / connector** (`createLine`),
  **table** (`createTable`), and **chart from Sheets** (`createSheetsChart`).
- **Group / ungroup** elements (`groupObjects`, `ungroupObjects`).

## Slides: edit geometry (all element types)

- **Move and resize** any element — position, scale, and rotation
  (`updatePageElementTransform`).
- **Reorder** elements front-to-back (`updatePageElementsZOrder`).

## Slides: edit appearance (all element types)

- **Image recolor and adjustments** (`updateImageProperties`): recolor, the
  adjustments — opacity (transparency), brightness, and contrast — plus crop,
  outline, and drop shadow.
- **Recolor and style, other types:** shape fill, outline, and drop shadow
  (`updateShapeProperties`); line properties (`updateLineProperties`); video
  properties (`updateVideoProperties`).
- **Tables:** insert and delete rows and columns, merge and unmerge cells, and
  cell / row / column / border properties (the `*Table*` requests).
- **Charts:** refresh a linked Sheets chart (`refreshSheetsChart`).

## Slides: edit text and links

- **Text blocks:** insert and delete text, and style runs and paragraphs
  (`insertText`, `deleteText`, `updateTextStyle`, `updateParagraphStyle`).
- **Bullets / lists:** add and remove list formatting (`createParagraphBullets`,
  `deleteParagraphBullets`).
- **Links:** set or clear a link on a text run (a `Link` in the text style, via
  `updateTextStyle`).

## Slides: alt text

- **Add, edit, or delete an image's alt text** — its `title` and `description`
  — on any element (`updatePageElementAltText`). "Delete" means clearing both
  fields; the API has no separate delete.

## Slides: presenter notes

- **Add, update, or delete the presenter notes** on a slide (the notes page
  text, edited through `presentations.batchUpdate`).

## Slides: delete

- **Delete a slide or any element** (`deleteObject`).
- **Add, reorder, or delete slides**, and **delete the whole presentation file**
  (Drive `files.delete`, or trash).

## Suggested order

1. **Create elements**, then **geometry** (move/resize/reorder).
2. **Appearance**, **text and links**, **alt text**, and **presenter notes**.
3. **Delete** and the slide/file structure operations.
