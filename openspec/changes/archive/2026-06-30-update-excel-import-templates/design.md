## Context

The Excel import pipeline:

```
User downloads template (.xlsx)    →  fills in rows  →  uploads file
       from /public/templates/                                 │
                                                               ▼
                        POST /api/v1/academic-ops/imports/students (multipart)
                                                               │
                                                               ▼
                        imports.rs::parse_students(bytes)
                          ├─ validate_headers (exact match on English names)
                          ├─ parse rows → Vec<CreateStudent>
                          └─ gender: .to_lowercase() (no translation!)
                                                               │
                                                               ▼
                        commands.rs::import_students
                          └─ validate_student_fields (gender must be male/female/other*)
                             (* becomes male/female only after Cluster D)
```

### Current template files

Located at `apps/web/public/templates/`:
- `students-template.xlsx` — 15 columns (English headers only)
- `teachers-template.xlsx` — 17 columns (English headers only)

The frontend `ImportDialog` (`import-dialog.tsx:94`) links to these via:
```tsx
<a href={templateHref} download>
```

### The column mapping audit

| `CreateStudent` field  | In template? | Notes |
|------------------------|--------------|-------|
| `nis`                  | ✅ required  |       |
| `nisn`                 | ✅           |       |
| `nik`                  | ✅           |       |
| `full_name`            | ✅ required  |       |
| `gender`               | ✅ required  | needs translation |
| `birth_date`           | ✅ required  | YYYY-MM-DD |
| `birth_place`          | ✅           |       |
| `address_line`         | ✅           |       |
| `phone_number`         | ✅           |       |
| `religion`             | ✅           |       |
| `nationality`          | ✅           |       |
| `child_order`          | ✅           | integer |
| `sibling_count`        | ✅           | integer |
| `entry_date`           | ✅           | YYYY-MM-DD |
| `origin_school`        | ✅           |       |
| `user_id`              | ❌           | internal, not importable |
| `initial_placement`    | ❌           | separate API |

| `CreateTeacher` field    | In template? | Notes |
|--------------------------|--------------|-------|
| `nip`                    | ✅ required  |       |
| `nik`                    | ✅           |       |
| `full_name`              | ✅ required  |       |
| `education_level`        | ✅           |       |
| `gender`                 | ✅           | needs translation |
| `birth_date`             | ✅           | YYYY-MM-DD |
| `birth_place`            | ✅           |       |
| `address_line`           | ✅           |       |
| `phone_number`           | ✅           |       |
| `email`                  | ✅           |       |
| `employment_status`      | ✅           |       |
| `role_position`          | ✅           |       |
| `start_date`             | ✅           | YYYY-MM-DD |
| `end_date`               | ✅           | YYYY-MM-DD |
| `primary_subject_area`   | ✅           |       |
| `nuptk`                  | ✅           |       |
| `certification_number`   | ✅           |       |
| `user_id`                | ❌           | internal |

**Finding**: all user-facing fields are already in the template. The issue is
NOT missing columns — it's that the templates lack **guidance** (labels,
examples, format hints). If the product owner wants MORE columns, those would
need to be new fields on the struct + DB migration, which is a separate
scope decision.

## Goals / Non-Goals

**Goals:**
- Templates are self-documenting: Indonesian labels, example row, format
  notes.
- Gender values in Indonesian (`laki-laki`/`perempuan`) are accepted by the
  importer via translation.
- The template endpoint returns metadata (labels, required flags) for
  potential dynamic UI rendering.

**Non-Goals:**
- Adding new data fields to the student/teacher model (separate scope).
- Changing the import validation logic beyond gender translation.
- Supporting CSV (only `.xlsx`/`.xls`/`.ods` via calamine).

## Decisions

### Decision 1: Keep English header as row 1, add Indonesian label as row 2

The backend's `validate_headers` does an exact case-insensitive match on the
English field names. Changing the header row would break this. Instead:

```
Row 1: nis | nisn | nik | full_name | gender | birth_date | ...
Row 2: NIS | NISN | NIK | Nama Lengkap | Jenis Kelamin | Tanggal Lahir | ...
Row 3: 1234567 | 9876543 | 3170... | Andi Saputra | laki-laki | 2010-05-15 | ...
```

Wait — this breaks `validate_headers` which expects row 1 to be the header
and skips row 1 for data. Two options:

**Option A**: The importer skips row 2 (Indonesian label row) during parsing.
This requires changing `parse_students`/`parse_teachers` to `skip(2)` instead
of `skip(1)` when a label row is detected. Fragile.

**Option B**: Keep row 1 as English headers (unchanged). Put Indonesian
labels and examples in a **second sheet** ("Petunjuk" / "Instructions")
rather than in the data sheet. The data sheet has only the English header +
blank rows. This is cleaner and doesn't require parser changes.

*Lean: Option B.* The data sheet stays parse-compatible; the guidance lives
in a separate sheet or in cell comments.

### Decision 2: Gender translation map

In `imports.rs`, add:
```rust
fn translate_gender(raw: &str) -> String {
    match raw.trim().to_lowercase().as_str() {
        "l" | "laki-laki" | "laki laki" | "pria" | "male" => "male",
        "p" | "perempuan" | "wanita" | "female" => "female",
        other => other, // let backend validation reject unknown values
    }.to_string()
}
```

Apply this in `parse_students` (line 63) and `parse_teachers` (line 99)
instead of `.to_lowercase()`.

This pairs with Cluster D: after D, only `male`/`female` are valid. The
translation ensures Indonesian input maps correctly.

### Decision 3: Template generation

Generate the `.xlsx` files programmatically using `rust_xlsxwriter` (already
in dev-dependencies for tests) or a Node script. The generated files
include:
- Sheet 1 ("Data"): English header row + blank rows (for user input).
- Sheet 2 ("Petunjuk"): column-by-column guide with Indonesian label,
  required/optional, format, and example.

Commit the generated files to `public/templates/`.

*Alternative rejected:* hand-craft in Excel. Rejected — not reproducible and
drifts from the backend column list.

## Risks / Trade-offs

- **[Risk] User ignores the Petunjuk sheet** → they still type bare English
  headers or wrong formats. *Mitigation:* the import error message
  (`INVALID_IMPORT_TEMPLATE`) already tells them the expected columns; the
  gender translation handles the most common mistake.
- **[Risk] Gender translation maps unexpected input** → e.g. "L" could be
  ambiguous. *Mitigation:* only map common Indonesian forms; unknown values
  pass through to validation which rejects them with a clear error.

## Migration Plan

1. **Backend**: add gender translation in `imports.rs`; enrich template
   endpoint. Deploy.
2. **Generate templates**: create a generation script (Rust or Node) that
   produces both `.xlsx` files from the column definitions. Run it; commit
   the output.
3. **Web**: verify the download links still work; update import dialog tests
   if needed.
4. **Verify**: download template → fill with Indonesian gender labels →
   upload → import succeeds.

## Open Questions

- Does the product owner want any NEW columns beyond what's already in the
  template? The current template already covers all user-facing fields. If
  new fields are needed, that's a separate model-change scope.
- Should the template endpoint (`GET /imports/template`) be used by the
  frontend to dynamically render column guidance, or is the static Petunjuk
  sheet sufficient? Lean: static sheet for now; dynamic rendering is a
  future enhancement.
