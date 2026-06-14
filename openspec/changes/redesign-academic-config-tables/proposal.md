## Why

The four `/settings/academic/*` tabs were each built ad-hoc and none match the
shadcn data-table standard the `/settings/users` and `/settings/roles` screens
were rebuilt on:

- **Tahun Ajaran** (`academic/years/page.tsx`) is a `divide-y` card list with a
  per-row status `Select`; no search, sort, pagination, edit, or delete.
- **Kurikulum** (`academic/curriculum/page.tsx`) is a two-panel master-detail
  (versions on the left, subjects on the right) driven by local `useState`, no
  edit/delete on either side.
- **Kebijakan Nilai** (`academic/grading-policy/page.tsx`) is a single upsert
  form gated by a `YearPicker` — it is not a collection at all.
- **Template Kelas** (`academic/class-templates/page.tsx`) is a form plus a
  read-only grid; no edit/delete.

The backend reinforces the gap. Every academic-config list endpoint returns a
**bare array** (`GET /academic-years` → `AcademicYear[]`) with no `meta`, and
the repo layer uses simple `list(tenant_id) -> Vec<_>` queries
(`academic-config-service/src/repo.rs`) — unlike IAM, which already does
`QueryBuilder` + filter + count + pagination (`iam-service/src/repo.rs:326`).
There are **no edit or delete endpoints** for curriculum versions, subjects, or
class templates; academic years support only create + status transition.

We are reorganizing the information architecture around the academic year as the
parent entity, then rebuilding everything on the server-driven data-table
pattern.

## What Changes

**Information architecture** — the academic year becomes the parent:

- `/settings/academic/years` is the **central data table**. Its create/edit modal
  is a scrolling, sectioned form that now also owns:
  - **§ Kebijakan Nilai** — the grading-policy upsert (min score + scale) moves
    here from its deleted standalone page.
  - **§ Versi Kurikulum** — an inline add/list/delete of curriculum versions for
    that year.
- **`/settings/academic/grading-policy` is removed** (BREAKING for the admin nav)
  — its form lives inside the year modal's Kebijakan Nilai section.
- **Subjects get their own data table** at a new `/settings/academic/subjects`,
  scoped by two filter dropdowns at the top: **Tahun Ajaran ▾** then **Versi
  Kurikulum ▾**. (Subjects are children of a curriculum version; keeping them in
  the year modal would push it three levels deep.)
- **Template Kelas** stays its own tab, rebuilt as a data table filtered by
  **Tahun Ajaran ▾**.

**Per-table behavior** (mirrors users/roles): server-driven search + sort +
pagination synced to the browser URL, a header/row multi-select checkbox column,
a per-row actions dropdown (Edit / Hapus), a bulk-delete flow confirmed via the
existing `AlertDialog`/`ConfirmDialog`, and create/edit modals built on `Dialog`.

**Backend (academic-config-service), per resource end-to-end:**

- Rework each list endpoint to accept `?search=&sort=&page=&page_size=` and
  return the `{ data, meta: { page, page_size, total } }` envelope, mirroring
  IAM's `QueryBuilder`/count pattern.
- Add the missing write endpoints:
  - Academic years: `DELETE /academic-years/{id}` + bulk delete.
  - Curriculum versions: `PATCH` (rename/description) + `DELETE` + bulk delete.
  - Subjects: `PATCH` (name/code/passing_grade) + `DELETE` + bulk delete.
  - Class templates: `PATCH` (grade_level/default_capacity) + `DELETE` + bulk
    delete.
- Deletes guard referential integrity (e.g. a year with curriculum versions,
  homerooms, or an active status is not silently destroyed) and continue to emit
  the existing outbox events where applicable.

## Capabilities

### New Capabilities
- `web-academic-config-management`: the admin-facing screens for managing
  academic years (with embedded grading policy + curriculum versions), subjects,
  and class templates as server-driven shadcn data tables.

### Modified Capabilities
- `academic-config-service`: list endpoints for academic years, curriculum
  versions, subjects, and class templates gain server-side search/sort/pagination
  with a populated `meta`; new edit (PATCH) and single + bulk delete endpoints are
  added for years, curriculum versions, subjects, and class templates, each
  guarding referential integrity.

## Impact

- **Backend:** `apps/backend/services/academic-config-service` (http routes,
  commands, repo list rework + PATCH/DELETE/bulk, integration tests). API
  contract doc
  `docs/internal/11_integration_contracts/apis/academic-config-service-api.md`.
- **Web:** `apps/web/src/app/settings/academic/years/page.tsx` (rebuilt),
  new `subjects/page.tsx`, `class-templates/page.tsx` (rebuilt),
  **removed** `grading-policy/page.tsx`; `academic-settings.tsx` nav updated
  (Kebijakan Nilai tab removed, Mata Pelajaran tab added). New
  `src/lib/schemas/academic-*-params.ts` per resource; extended
  `use-academic-config` queries (params + `meta` types) and mutations
  (patch/delete/bulk-delete). Reuses `DataTable`, `AlertDialog`/`ConfirmDialog`,
  `MultiSelect`, and `@tanstack/react-table` already in the repo.
- **Non-goals:** no change to the academic-year lifecycle state machine, the
  one-active-year rule, or the `academic_year.created` event contract; the
  grading-policy storage model (one upserted row per year) is unchanged — only
  its UI location moves.
