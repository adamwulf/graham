# Roadmap

What is still to do. For what already works, see `README.md`. For the
architecture and the recipes that show how to add each kind of feature, see
`CLAUDE.md`.

The focus is comprehensive Google Slides support — read and write for **every**
page-element type — plus file creation. Writes are mostly POST `batchUpdate`
endpoints with request bodies. `GoogleAPI.sendJSON(_:method:url:body:)` already
exists; add request-body models under `Models/` as each feature lands.

## Create files

- **Create a Doc, a Sheet, or a Slides file.** Make a new, empty Google Doc,
  spreadsheet, or presentation and print its id. Use the service `create`
  endpoint (for example Slides `presentations.create`) or Drive `files.create`
  with the right `mimeType`.

## Slides: model foundation

The current `PageElement` model reads only `objectId` and shapes. Extend it to
decode the common properties on every element and each element type. This
foundation unblocks all the read and write work below.

- **Common properties** on every page element: `objectId`, `size`,
  `transform` (position, scale, rotation), `title` and `description` (alt text).
- **All element types** (exactly one per page element): shape (this includes
  text boxes / text blocks and placeholders), image, video, line/connector,
  table, chart from Sheets (`sheetsChart`), word art, and grouped elements
  (`elementGroup`, which nests more page elements).

## Slides: read

- **List a presentation's slides and their elements.** For each slide, print
  every element with its type, position and size, text, links, and alt text.
- **Fetch the images on each slide.** List and download the images (the image
  `contentUrl`), and read each image's alt text.

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

1. **Create files** and the **model foundation** first — create gives us a file
   to work on, and the extended `PageElement` model unblocks every read and
   write.
2. **Read** (slides + elements), which surfaces the object ids that every edit
   needs.
3. **Create elements**, then **geometry** (move/resize/reorder).
4. **Appearance**, **text and links**, **alt text**, and **presenter notes**.
5. **Delete** and the slide/file structure operations.
