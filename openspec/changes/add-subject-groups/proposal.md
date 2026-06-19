## Why

Report cards currently render every subject as a flat list with no grouping.
Schools need to organize subjects into tenant-defined groups (e.g. "Kelompok A",
"Muatan Lokal", "Ekstrakurikuler") purely for **report-card presentation**.
This change introduces a `subject_group` layer above `subject` inside a
curriculum version. Groups are tenant-defined metadata only — they do not
affect grading formulas, evaluation scopes, or score computation, which remain
keyed on `subject_id`.

## What Changes

- **New resource `subject_group`** scoped per `curriculum_version`, carrying
  `name`, optional `code`, and a `position` controlling report-card ordering.
  Full CRUD with tenant-scoped list + single/bulk delete (all-or-nothing),
  mirroring the existing academic-config resource pattern.
- **Auto-create a default group** named `DEFAULT_SUBJECT_GROUP_NAME` ("Umum")
  at `position 1` whenever a curriculum version is created. The name is stored
  as a single configurable constant so tenants can adjust it later.
- **BREAKING — Subject now requires `subject_group_id`.** `POST /subjects` and
  `PATCH /subjects` MUST accept and persist `subject_group_id`. Existing
  subjects are migrated into their curriculum version's default "Umum" group.
- **Subject API responses** (`GET /subjects`, create/update) MUST include the
  resolved `subject_group_id` and a group summary (`name`, `code`, `position`)
  so the web can group without extra fetches.
- **Web Mata Pelajaran page** groups subjects visually by kelompok, with inline
  add/edit/delete/reorder of groups scoped to the selected curriculum version.
- **Report-card rendering** (web and portal) groups subject scores by
  `subject_group.position` then subject name. Scores and formulas are unchanged.

## Capabilities

### New Capabilities

(none — subject groups extend existing capabilities, they do not introduce a
standalone service contract)

### Modified Capabilities

- `academic-config-service`: new `subject_group` resource endpoints + subject
  gains required `subject_group_id`; default group auto-created on curriculum
  version creation.
- `web-academic-config-management`: Mata Pelajaran page groups by kelompok with
  group CRUD/reorder; subject form requires group selection.
- `web-report-cards`: report-card and portal rendering groups subject scores by
  `subject_group`.

## Impact

- **Backend `academic-config-service`**: new migration (`subject_group` table +
  `subject.subject_group_id` column + backfill to default "Umum"), domain/repo
  for `SubjectGroup`, commands for group CRUD + auto-default on curriculum
  create, query changes to include group metadata in subject responses, delete
  guards (`SUBJECT_GROUP_IN_USE` when it still has subjects), integration tests.
- **Backend `grading-service`**: **no data/schema change.** Report-card query
  that assembles subject scores MAY optionally join/call academic-config group
  metadata for grouped output, or the web resolves grouping client-side from
  the subject list — to be decided in design.
- **Web**: new query/mutation hooks for subject groups, Mata Pelajaran page
  redesign (group sections + subject rows), report-card detail/portal grouping,
  Zod schemas updated, academic scope unchanged.
- **Docs**: update
  `docs/internal/10_data_design/03_Academic_Config_Service_ERD.md` and
  `docs/internal/11_integration_contracts/apis/academic-config-api.md`.
- **Migration risk**: backfill on existing subjects; default group name as a
  constant (`DEFAULT_SUBJECT_GROUP_NAME = "Umum"`) defined once and reused.
