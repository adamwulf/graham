# Roadmap

What is still to do. For completed features and commands, see `README.md`. For
architecture and implementation conventions, see `CLAUDE.md`.

The remaining focus is comprehensive Google Slides write support. Slides
writes use `presentations.batchUpdate` with typed request bodies. File
creation, the complete nine-type page-element model, detailed element reading,
image listing/download, and the slide lifecycle (the shared batch-update
foundation plus `slides add`, `slides move`, and `slides delete`) are complete.

## Next milestone: create elements

Add every element type that the Slides batch-update API can create. New
operations join the existing `SlidesBatchUpdateRequest` union, so they share
the tested batch-update path; keep the client owning the request bodies and
the CLI thin.

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

1. **Create elements** — the next milestone defined above, beginning with a
   text box plus inserted text.
2. **Geometry**, then **appearance**.
3. **Text and links**, **alt text**, and **presenter notes**.
4. **General element deletion** and whole-presentation deletion or trash.
