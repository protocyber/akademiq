## MODIFIED Requirements

### Requirement: The web app SHALL provide a reusable drag-and-drop file dropzone

The web app MUST provide a reusable `FileDropzone` component
(`src/components/ui/file-dropzone.tsx`) that accepts a single file via both
drag-and-drop and click-to-browse, styled with shadcn tokens. It MUST accept an
`accept` (MIME/extension) constraint and an optional `maxSize`, MUST reject files
that fail those constraints with inline feedback, and MUST show the selected
file's name (and size) with a control to clear the selection. The component MUST
be generic (not import-specific) so it can be reused outside spreadsheet import.

All single-image upload surfaces — profile avatar, school logo, and
teacher/student photo — MUST use `FileDropzone` (configured with an
`accept="image/*"` constraint and a 2MB `maxSize`) instead of a bare
`<input type="file">`.

#### Scenario: File chosen by drag-and-drop

- **WHEN** a user drags a `.xlsx` file onto the dropzone
- **THEN** the file is accepted, its name and size are shown, and the consumer receives the file via `onChange`

#### Scenario: Disallowed file type is rejected

- **WHEN** a user drops a file whose type is outside the `accept` constraint
- **THEN** the dropzone rejects it with readable inline feedback and `onChange` is not called with that file

#### Scenario: Image upload surfaces reuse the dropzone

- **WHEN** a user opens the avatar, school-logo, or teacher/student photo upload
- **THEN** the upload UI is the shared `FileDropzone` constrained to images up to 2MB, and an over-limit or non-image file is rejected with inline feedback
