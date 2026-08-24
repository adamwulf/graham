# Roadmap

What is still to do. For completed features and commands, see `README.md`. For
architecture and implementation conventions, see `CLAUDE.md`.

The remaining focus is comprehensive Google Slides write support. Slides
writes use `presentations.batchUpdate` with typed request bodies. File
creation, the complete nine-type page-element model, detailed element reading,
image listing/download, and the slide lifecycle (the shared batch-update
foundation plus `slides add`, `slides move`, and `slides delete`) are complete.
Shape/text-box creation and basic text insertion are also complete, as is
creating images, videos, lines, tables, and Sheets charts and grouping and
ungrouping elements. Element geometry can be moved, scaled, rotated,
transformed directly, and reordered front-to-back.

## Next milestone: edit appearance

- **Image recolor and adjustments** (`updateImageProperties`): opacity,
  brightness, contrast, crop, outline, and drop shadow.
- **Other element styles:** shape fill, outline, and drop shadow
  (`updateShapeProperties`); line properties (`updateLineProperties`); video
  properties (`updateVideoProperties`).
- **Tables:** insert/delete rows and columns, merge/unmerge cells, and edit
  cell, row, column, and border properties (the `*Table*` requests).
- **Charts:** refresh a linked Sheets chart (`refreshSheetsChart`).

## Slides: edit text and links

- **Text blocks:** delete text and style runs and paragraphs
  (`deleteText`, `updateTextStyle`, `updateParagraphStyle`).
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

## Slides: layouts

A slide's layout is chosen at creation, and each deck carries its own layout
list (`layouts[]` on `presentations.get`); graham does not decode it yet.

- **Read layouts.** Extend `Presentation` with `layouts`, and add a
  `slides layouts` command that lists each layout's object id and display
  name. Follow the `elementRows` pattern: extraction in `GrahamKit`, a thin
  command that renders `GrahamRow`s.
- **`slides add --layout-id <id>`.** Send `slideLayoutReference.layoutId`
  (the model already supports it). A deck can lack a given predefined layout
  name, which makes Google reject the add; a real layout id from
  `slides layouts` always works. Reject `--layout` and `--layout-id` given
  together.

## Drive: copy files

- **`graham drive copy <file-id> [--name <name>]`** through `files.copy`,
  with `supportsAllDrives=true`, printing the new file id like
  `drive create`.

## Slides: delete objects and files

- Extend the exact-ID delete operation from slides to any page element
  (`deleteObject`).
- Delete the entire presentation through Drive `files.delete`, or add a
  deliberate trash operation.

## Suggested order

1. **Appearance**.
2. **Layouts read facade, `slides add --layout-id`, and `drive copy`** —
   small and independent; they can land alongside any milestone.
3. **Text and links**, **alt text**, and **presenter notes**.
4. **General element deletion** and whole-presentation deletion or trash.
