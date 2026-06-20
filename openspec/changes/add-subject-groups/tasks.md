## 1. Backend: data model & migration

- [x] 1.1 Add `DEFAULT_SUBJECT_GROUP_NAME` constant (value `"Umum"`) in `academic-config-service/src/domain.rs` (or a new `constants` module) as the single source of truth.
- [x] 1.2 Create migration (next versioned file) that: (a) creates `subject_group` table `(subject_group_id PK, tenant_id, curriculum_version_id FK, name, code, position, created_at, updated_at)` with index on `curriculum_version_id` and unique `(tenant_id, curriculum_version_id, code)`; (b) for each existing `curriculum_version`, inserts one "Umum" group at `position 1` using the same constant value; (c) adds nullable `subject.subject_group_id`; (d) backfills every subject to its curriculum version's default group; (e) `ALTER ... SET NOT NULL`; (f) adds FK `subject.subject_group_id → subject_group(subject_group_id) ON DELETE RESTRICT`. Dev-reset acceptable per precedent.

## 2. Backend: domain & repository

- [x] 2.1 Add `SubjectGroup` domain struct and request/response DTOs (`name`, optional `code`, `position`).
- [x] 2.2 Add `SubjectGroupRepo`: `insert`, `list_for_curriculum`, `count_for_curriculum`, `find_by_id`, `update`, `delete`, `delete_bulk`, `count_subjects`, `exists`; `SubjectGroupSort` whitelist (`name`, `-name`, `position`, `-position`, `created_at`, `-created_at`).
- [x] 2.3 Extend `Subject` domain/DTOs with required `subject_group_id` and a `subject_group` summary (`name`, `code`, `position`); update `SubjectRepo` insert/update/list to carry and join group metadata.

## 3. Backend: commands & queries

- [x] 3.1 Add commands: `add_subject_group` (validates name, ensures curriculum version exists for tenant), `update_subject_group`, `delete_subject_group` (guard `SUBJECT_GROUP_IN_USE` via in-db count), `bulk_delete_subject_groups` (all-or-nothing).
- [x] 3.2 Update `add_curriculum_version` to auto-create the default group (`DEFAULT_SUBJECT_GROUP_NAME`, `position 1`) in the same transaction.
- [x] 3.3 Update `add_subject`/`update_subject` to accept and validate `subject_group_id` (must belong to the same curriculum version + tenant); reject missing id with `VALIDATION_ERROR` field error on `subject_group_id`.
- [x] 3.4 Add/extend queries: `list_subject_groups` (search/sort/page envelope) and ensure `list_subjects` returns the group summary.

## 4. Backend: HTTP routes

- [x] 4.1 Add routes under `/api/v1/academic-config/curriculum-versions/:curriculum_version_id/subject-groups`: `GET` (list) and `POST`.
- [x] 4.2 Add `PATCH /api/v1/academic-config/subject-groups/:subject_group_id`, `DELETE` single, and `POST /subject-groups/bulk/delete`.
- [x] 4.3 Update `POST`/`PATCH /subjects` request validation to require `subject_group_id`; ensure `GET /subjects` responses include the group summary.
- [x] 4.4 Enforce `academic.config.read` on group GET and write permissions on group mutations, matching the existing academic-config permission model.

## 5. Backend: tests

- [x] 5.1 Integration test: creating a curriculum version auto-creates the "Umum" group at position 1.
- [x] 5.2 Integration test: subject CRUD requires and validates `subject_group_id`; responses carry the group summary.
- [x] 5.3 Integration test: group CRUD + list pagination/sort/search + `INVALID_SORT`.
- [x] 5.4 Integration test: `delete`/`bulk-delete` group guarded by `SUBJECT_GROUP_IN_USE`; all-or-nothing semantics.
- [x] 5.5 Integration test: moving a subject to a group in another curriculum version is rejected.

## 6. Web: data layer

- [x] 6.1 Add `SubjectGroup` type and query/mutation hooks in `use-academic-config.ts`: list groups for a curriculum version, add/update/delete/bulk-delete group.
- [x] 6.2 Extend `Subject` type with `subject_group_id` + `subject_group` summary; update `subjectSchema` to require `subject_group_id` (and a group selector value).
- [x] 6.3 Add `academic-subject-groups-params` URL params/schema (search, sort, page, page_size) mirroring the subjects params pattern, or extend the subjects params as appropriate.

## 7. Web: Mata Pelajaran page

- [x] 7.1 Redesign `/settings/academic/subjects` to render collapsible **Kelompok** sections (ordered by `position`) each containing a subjects data table; keep year→version cascading filters and URL sync.
- [x] 7.2 Add kelompok management UI inside the selected curriculum version: add (name, optional code, position), edit, delete (surface `SUBJECT_GROUP_IN_USE`), reorder (position).
- [x] 7.3 Update the subject create/edit Dialog to include a **Kelompok** selector defaulting to the first group; keep name/code/passing-grade fields and bulk-delete flow.
- [x] 7.4 Update `academic-settings.tsx` nav if needed (no separate Kelompok entry; confirm "Mata Pelajaran" remains).

## 8. Web: report cards & portal grouping

- [x] 8.1 In the report-card detail modal + print route, group `report_subject_score` rows by kelompok (ordered by `group.position` then subject name); render group headers.
- [x] 8.2 In `/portal/report-card`, render published report-card subject scores grouped by kelompok the same way.
- [x] 8.3 Handle unresolved-group subjects gracefully (do not silently drop; render under the returned group summary).

## 9. Docs

- [x] 9.1 Update `docs/internal/10_data_design/03_Academic_Config_Service_ERD.md`: add `SUBJECT_GROUP` entity, relations, invariants (every curriculum version ≥1 group; every subject has a group), and the default-group rule.
- [x] 9.2 Update `docs/internal/11_integration_contracts/apis/academic-config-api.md`: document `subject-group` endpoints, the breaking `subject_group_id` on subject create/update, and group summary in subject responses.
- [x] 9.3 Note the breaking change (subject API) and the `DEFAULT_SUBJECT_GROUP_NAME` constant in the relevant doc section.

## 10. Validation

- [x] 10.1 Run `openspec validate add-subject-groups` and fix any reported issues.
- [x] 10.2 Run backend lint + tests (`cd apps/backend && make test`) for academic-config-service.
- [x] 10.3 Run web lint + typecheck + tests (`cd apps/web && make test` / lint) for affected pages.
