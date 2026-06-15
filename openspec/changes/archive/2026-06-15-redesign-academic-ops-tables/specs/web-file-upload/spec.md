## ADDED Requirements

### Requirement: The web app SHALL provide a reusable drag-and-drop file dropzone

The web app MUST provide a reusable `FileDropzone` component
(`src/components/ui/file-dropzone.tsx`) that accepts a single file via both
drag-and-drop and click-to-browse, styled with shadcn tokens. It MUST accept an
`accept` (MIME/extension) constraint and an optional `maxSize`, MUST reject files
that fail those constraints with inline feedback, and MUST show the selected
file's name (and size) with a control to clear the selection. The component MUST
be generic (not import-specific) so it can be reused outside spreadsheet import.

#### Scenario: File chosen by drag-and-drop

- **WHEN** a user drags a `.xlsx` file onto the dropzone
- **THEN** the file is accepted, its name and size are shown, and the consumer receives the file via `onChange`

#### Scenario: Disallowed file type is rejected

- **WHEN** a user drops a file whose type is outside the `accept` constraint
- **THEN** the dropzone rejects it with readable inline feedback and `onChange` is not called with that file

### Requirement: Spreadsheet import SHALL be available as a reusable dialog on the relevant screens

The web app MUST provide a reusable `ImportDialog` that wraps `FileDropzone`, a
download-template link, the import action, and a row-level error report for failed
validation. It MUST be launched from an **[Impor ▾]** control on the `/students`
and `/teachers` screens. The standalone `/import` page MUST be removed and the
operational navigation MUST NOT include an Import entry.

#### Scenario: Import a valid sheet from the students screen

- **WHEN** an admin opens the import dialog from `/students`, drops a valid sheet, and submits
- **THEN** the import runs, a success summary is shown, and the students table reflects the imported rows

#### Scenario: Row-level errors are reported in the dialog

- **WHEN** an admin imports a sheet with an invalid row
- **THEN** the dialog shows the per-row error report and no rows are persisted

#### Scenario: The standalone import page is gone

- **WHEN** a user navigates to `/import`
- **THEN** the standalone page no longer exists and import is reached via the [Impor ▾] control on `/students` and `/teachers`
