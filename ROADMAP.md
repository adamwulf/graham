# Roadmap

What is still to do. For what already works, see `README.md`. For the
architecture and the recipes that show how to add each kind of feature, see
`CLAUDE.md`.

The focus is Google Slides, plus file creation. Writes are mostly POST
`batchUpdate` endpoints with request bodies. `GoogleAPI.sendJSON(_:method:url:body:)`
already exists; add request-body models under `Models/` as each feature lands.

## Create files

1. **Create a Doc, a Sheet, or a Slides file.** Make a new, empty Google Doc,
   spreadsheet, or presentation and print its id. Use the service `create`
   endpoint (for example Slides `presentations.create`) or Drive `files.create`
   with the right `mimeType`.

## Read Slides

2. **List a presentation's slides and their contents.** Read a Slides file and
   print each slide with its text (title, body, and other text on the slide).
   Builds on `SlidesClient.presentation(id:)`; add a command that walks the
   slides and renders their text.
3. **Fetch the images on each slide.** For a presentation, list the images per
   slide and download them (the image `contentUrl` per page element), and read
   each image's alt text (its `title` and `description`).

## Edit Slides

4. **Add, update, or delete a slide** inside a presentation
   (`presentations.batchUpdate`: `createSlide`, element updates, `deleteObject`).
5. **Add or delete a Slides file** (create covered by item 1; delete via Drive
   `files.delete`, or trash). "Update" of the whole file means its content,
   covered by items 4 and 6.
6. **Add, update, or delete the presenter notes** on a slide (the notes page
   text, edited through `presentations.batchUpdate`).
7. **Add, edit, or delete an image's alt text** — its `title` and `description`
   — on any slide, through `presentations.batchUpdate` with an
   `updatePageElementAltText` request. "Delete" means clearing both fields; the
   API has no separate delete. This also needs the `PageElement` model extended
   to decode `title`, `description`, and the `image` field, which it currently
   ignores (that same extension serves the reads in items 2 and 3).

## Suggested order

Build **item 1** (create) and **item 2** (read slides) first: create gives us a
file to work on, and read gives us the object ids that every edit needs. Extend
the `PageElement` model early, since items 2, 3, and 7 all need it. Then the
edits (items 4, 6, and 7), then item 3 (images) and the delete part of item 5.
