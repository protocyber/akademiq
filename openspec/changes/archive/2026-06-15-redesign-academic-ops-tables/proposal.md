## Why

The four operational screens (`/students`, `/teachers`, `/homerooms`,
`/teaching-assignments`) and the separate `/import` page are all rendered by a
single dense module, `components/features/academic-ops/academic-ops-page.tsx`,
built on bespoke `List`/`ResourceCard` helpers and inline forms. None of them use
the shadcn data-table standard the `/settings/users` and `/settings/roles`
screens were rebuilt on — there is no search, sort, pagination, multi-select,
per-row actions dropdown, or bulk delete anywhere.

Import is a dimension of the problem: it lives on its own `/import` route as two
`<input type="file">` boxes (`ImportPanel`), disconnected from the student/teacher
screens it actually feeds, and there is no drag-and-drop affordance.

The backend reinforces the gap. Every list endpoint returns a **bare array**
(`StudentRepo::list(tenant_id) -> Vec<Student>` in
`academic-ops-service/src/repo.rs:34`) with no `meta`, and there are **no delete
endpoints** for students, teachers, homerooms, or teaching assignments
(only enrollment has `unenroll`). Students support `PATCH`; teachers, homerooms,
and assignments have no edit. This is unlike IAM, which already does
`QueryBuilder` + filter + count + pagination.

## What Changes

**Per-screen rebuild on the server-driven data-table pattern** (search + sort +
pagination synced to the browser URL, header/row multi-select, per-row actions
dropdown, bulk delete confirmed via the existing AlertDialog/ConfirmDialog,
create/edit `Dialog` modals):

- **`/students`** — data table (NIS, Nama, Gender, Tgl Lahir), create/edit modal,
  bulk delete, and a header **[Impor ▾]** button opening an import modal.
- **`/teachers`** — data table (NIP, Nama, **Akun**), create/edit modal, bulk
  delete, and a header **[Impor ▾]** button. The teacher↔login-account link
  (currently an inline `QuerySelect` in the cell) moves to a **"Hubungkan akun"**
  action in the per-row dropdown that opens a user-picker modal. *(The account
  link stays first-class: a teacher is master data that can exist before a login
  account; `teaching_assignment`/`grade` reference `teacher_id` while auth uses
  `user_id`, so the link is what lets a teacher log in to see classes and grade —
  the Akun column is the readiness signal.)*
- **`/homerooms`** — data table of classes (Nama, Tingkat, Tahun, Kapasitas),
  create/edit modal, bulk delete, and a per-row **"Roster"** action opening a
  modal with the class roster as its own table plus enroll/unenroll.
- **`/teaching-assignments`** — data table (Guru, Mapel, Kelas, Tahun) with
  filter dropdowns (Tahun/Kurikulum/Kelas), a **[Tambah Penugasan]** button
  opening the chained form in a modal, and per-row delete.

**Import relocation (BREAKING for nav):**

- The standalone **`/import` page is removed**. Import becomes a reusable
  **`ImportDialog`** (download-template link + drag-and-drop dropzone + row-level
  error report) launched from the **[Impor ▾]** button on `/students` and
  `/teachers`.

**New reusable components (live in this change, written generically):**

- **`src/components/ui/file-dropzone.tsx`** — a shadcn-styled drag-and-drop file
  input built on **`react-dropzone`** (new dependency), with click-to-browse,
  `.xlsx/.xls/.ods` type validation, and selected-file preview.
- **`ImportDialog`** — the import modal wrapping `FileDropzone`, reused by both
  student and teacher screens.

**Backend (academic-ops-service), per resource end-to-end:**

- Rework each list endpoint (`students`, `teachers`, `homerooms`,
  teaching-assignment list) to accept `?search=&sort=&page=&page_size=` and
  return `{ data, meta }`, mirroring IAM's `QueryBuilder`/count pattern.
- Add the missing write endpoints: teacher `PATCH`; single + bulk `DELETE` for
  students, teachers, homerooms, and teaching assignments, each guarding
  referential integrity (e.g. a student with an active enrollment, a homeroom
  with a roster, a teacher with assignments).

## Capabilities

### New Capabilities
- `web-academic-ops-management`: the operational screens (students, teachers,
  homerooms, teaching assignments) as server-driven shadcn data tables with
  per-screen import where applicable.
- `web-file-upload`: a reusable drag-and-drop file dropzone and import dialog.

### Modified Capabilities
- `academic-ops-service`: list endpoints for students, teachers, homerooms, and
  teaching assignments gain server-side search/sort/pagination with a populated
  `meta`; new teacher edit (PATCH) and single + bulk delete endpoints are added
  for students, teachers, homerooms, and teaching assignments, each guarding
  referential integrity.

## Impact

- **Backend:** `apps/backend/services/academic-ops-service` (http routes,
  commands, repo list rework + PATCH/DELETE/bulk, integration tests). API
  contract doc
  `docs/internal/11_integration_contracts/apis/academic-ops-service-api.md`.
- **Web:** new `src/components/ui/file-dropzone.tsx` and an `ImportDialog`;
  rebuilt `app/students`, `app/teachers`, `app/homerooms`,
  `app/teaching-assignments` pages; **removed** `app/import`; `academic-ops-page.tsx`
  refactored or replaced (opsNav loses the Import entry). New
  `src/lib/schemas/*-params.ts` per resource; extended `use-academic-ops`
  queries (params + `meta`) and mutations (patch/delete/bulk). New dependency
  `react-dropzone` in `apps/web/package.json`. Reuses `DataTable`,
  `AlertDialog`/`ConfirmDialog`, `QuerySelect`, `MultiSelect`.
- **Non-goals:** no change to the import validation/rollback contract, the
  one-active-enrollment rule, the `student.enrolled`/`teacher.assigned` event
  contracts, or the teacher-account link semantics (only its UI placement moves).
