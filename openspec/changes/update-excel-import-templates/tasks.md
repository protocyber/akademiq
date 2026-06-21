# Tasks: update-excel-import-templates

Backend submodule `apps/backend`, web submodule `apps/web`.

## 1. Backend — gender translation

- [ ] 1.1 In `imports.rs`, add `translate_gender(raw: &str) -> String` with
      the mapping: laki-laki/laki laki/pria/l → male;
      perempuan/wanita/p → female; male/female pass through; unknown passes
      through.
- [ ] 1.2 In `parse_students` (line 63): replace `.to_lowercase()` with
      `translate_gender(&cell_string(row.get(4)))`.
- [ ] 1.3 In `parse_teachers` (line 99): replace `.map(|s| s.to_lowercase())`
      with `.map(|s| translate_gender(&s))`.
- [ ] 1.4 Unit test: "Laki-laki" → male; "perempuan" → female; "male" →
      male; "xyz" → "xyz" (passthrough).

## 2. Backend — template endpoint enrichment

- [ ] 2.1 In `http.rs` `import_template` handler: return a JSON structure
      with both student and teacher column lists, each entry having
      `{ field, label, required, format }`.
- [ ] 2.2 Add Indonesian labels for each column (e.g. full_name → "Nama
      Lengkap", birth_date → "Tanggal Lahir", gender → "Jenis Kelamin").
- [ ] 2.3 Mark required columns (`nis`, `full_name`, `gender`, `birth_date`
      for students; `nip`, `full_name` for teachers).

## 3. Web — regenerate template files

- [ ] 3.1 Write a generation script (Node, using a library like `exceljs`,
      or Rust using `rust_xlsxwriter`) that reads the column definitions
      (hardcoded or fetched from the endpoint) and generates:
      - Sheet 1 "Data": English headers in row 1.
      - Sheet 2 "Petunjuk": column guide with Indonesian label, required,
        format, example.
- [ ] 3.2 Generate `students-template.xlsx` and `teachers-template.xlsx`.
- [ ] 3.3 Commit the generated files to `apps/web/public/templates/`.
- [ ] 3.4 Verify the download links in `import-dialog.tsx` still point to
      the correct files.

## 4. Verification

- [ ] 4.1 `make test` (backend + web) green.
- [ ] 4.2 Download template → fill "Data" sheet with Indonesian gender
      labels → upload → import succeeds.
- [ ] 4.3 Verify the "Petunjuk" sheet renders correctly in Excel/LibreOffice.
