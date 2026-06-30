## Why

The student and teacher Excel import templates
(`apps/web/public/templates/students-template.xlsx` and
`teachers-template.xlsx`) are static `.xlsx` files with **bare English column
headers** (`nis`, `nisn`, `full_name`, etc.) and no example rows, no
Indonesian labels, and no data-format guidance. Users importing real data
struggle because:

1. Column headers are raw field names (e.g. `child_order`, `sibling_count`)
   that aren't self-explanatory in Indonesian.
2. There are no example rows showing expected formats (date format
   `YYYY-MM-DD`, gender values `male`/`female`, etc.).
3. The gender column expects lowercase English (`male`/`female`) but the UI
   labels are Indonesian — users type "Laki-laki" which silently fails
   validation.
4. The backend `validate_headers` (`imports.rs:130-152`) does an exact
   case-insensitive match on the raw English field names, so the template
   and the import file MUST use those exact headers.

The product request is: "perbaiki template excel untuk import siswa dan
guru. kolom siswa dan guru sekarang lebih banyak."

## What Changes

- **Regenerate the static `.xlsx` template files** in
  `apps/web/public/templates/` with:
  - Indonesian-friendly column headers (second header row or a header
    comment) — keep the raw English header as row 1 (required by the
    backend's `validate_headers` exact match), add an Indonesian label row
    or a comment.
  - One example data row demonstrating valid formats (date as
    `YYYY-MM-DD`, gender as `male`/`female`, numbers for `child_order`/
    `sibling_count`).
  - A second sheet or notes section documenting: required vs optional
    columns, date format, gender values, and the full column list.
- **Add any new columns** if the struct has fields not yet in the template
  (audit: `CreateStudent` and `CreateTeacher` against
  `STUDENT_TEMPLATE_COLUMNS` / `TEACHER_TEMPLATE_COLUMNS`).
- **Backend `GET /imports/template`**: update to return the current column
  list with Indonesian labels and required/optional flags so the frontend
  can render dynamic guidance.
- **Gender translation in import**: the importer currently lowercases gender
  but does NOT translate Indonesian labels. Add a mapping
  (`"laki-laki" → "male"`, `"perempu" → "female"`) so Indonesian Excel input
  works. This pairs with Cluster D (gender values restricted to male/female).

## Capabilities

### Modified Capabilities
- `academic-ops-service`: import gender translation; template endpoint
  enriched with labels/metadata.
- `web-academic-ui`: regenerated template `.xlsx` files with guidance.

## Impact

- **Backend** (`apps/backend`):
  - `services/academic-ops-service/src/imports.rs`: add gender translation
    map; update `STUDENT_TEMPLATE_COLUMNS` / `TEACHER_TEMPLATE_COLUMNS` if
    new columns are added.
  - `http.rs` `import_template` handler: enrich response with labels.
- **Web** (`apps/web`):
  - `public/templates/students-template.xlsx` and `teachers-template.xlsx`:
    regenerated files.
  - The import dialog (`import-dialog.tsx`) and its tests may need updates
    if the template href changes.
- **No DB migration.**
