# Roadmap

What is still to do. For completed features and commands, see `README.md`. For
architecture and implementation conventions, see `CLAUDE.md`.

## Next milestone: alt text and presenter notes

- **Alt text:** add, edit, or clear alt text on any page element through
  `updatePageElementAltText`. Clearing both `title` and `description` is the API
  equivalent of deleting alt text.
- **Presenter notes:** add, update, or delete presenter notes by editing the
  notes-page text through `presentations.batchUpdate`.

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

1. **Alt text** and **presenter notes**.
2. **Layouts read facade, `slides add --layout-id`, and `drive copy`** —
   small and independent; they can land alongside any milestone.
3. **General element deletion** and whole-presentation deletion or trash.
