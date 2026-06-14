# Tasks — redesign-academic-config-tables

Work is ordered **per resource, end-to-end** (backend → web) so each resource
becomes fully functional before moving on. Backend mirrors the IAM
`QueryBuilder`/count + all-or-nothing bulk-delete patterns.

## 1. Academic years — backend

- [x] 1.1 Rework `AcademicYearRepo::list` (`academic-config-service/src/repo.rs:66`) into a `QueryBuilder` with case-insensitive name search, whitelisted `ORDER BY` (name/start_date/status), and `LIMIT/OFFSET`; add `count_academic_years(params)`
- [x] 1.2 Add `ListAcademicYearsParams` + `PaginatedAcademicYears` in `queries.rs`; add `AcademicYearSort::parse` rejecting unknown keys with `INVALID_SORT`
- [x] 1.3 Add `AcademicYearsQuery` extractor and update `list_academic_years` (`http.rs:118`) to parse params and return `{ data, meta }`
- [x] 1.4 Add `DELETE /academic-years/:id` (`delete_academic_year`) + a bulk-delete route; command guards `ACTIVE_YEAR_IMMUTABLE` (status Active) and `YEAR_IN_USE` (homeroom/teaching-assignment references — query the ops projection or cross-service check per existing pattern)
- [x] 1.5 Add integration tests: paginated list + search/sort, `INVALID_SORT`, delete active year (409), delete in-use year (409), delete deletable year (200), bulk delete all-or-nothing
- [x] 1.6 `cd apps/backend && make test` green

## 2. Curriculum versions — backend

- [x] 2.1 Rework `list_for_year` into paginated `{ data, meta }` with search/sort; add count
- [x] 2.2 Add `PATCH /curriculum-versions/:id` (name, description) and `DELETE` + bulk; delete guards `CURRICULUM_IN_USE` when subjects exist
- [x] 2.3 Integration tests (patch, delete guarded/allowed, bulk all-or-nothing) + `make test`

## 3. Subjects — backend

- [x] 3.1 Rework `list_for_curriculum` into paginated `{ data, meta }` with search (name/code) + sort (name/code/passing_grade) + count
- [x] 3.2 Add `PATCH /subjects/:id` (name, code, passing_grade) and `DELETE` + bulk; delete guards `SUBJECT_IN_USE` when a teaching assignment references it
- [x] 3.3 Integration tests + `make test`

## 4. Class templates — backend

- [x] 4.1 Rework `list_for_year` into paginated `{ data, meta }` with search (grade_level) + sort + count
- [x] 4.2 Add `PATCH /class-templates/:id` (grade_level, default_capacity) and `DELETE` + bulk (always deletable)
- [x] 4.3 Integration tests + `make test`

## 5. Backend — contract docs

- [x] 5.1 Document the new query params + `{ meta }` and the PATCH/DELETE/bulk-delete endpoints (with guard codes `ACTIVE_YEAR_IMMUTABLE`, `YEAR_IN_USE`, `CURRICULUM_IN_USE`, `SUBJECT_IN_USE`, `INVALID_SORT`) in `docs/internal/11_integration_contracts/apis/academic-config-service-api.md`

## 6. Web — query/mutation layer + params schemas

- [x] 6.1 Extend `use-academic-config.ts` queries: accept params, type the `{ data, meta }` envelope for years/curriculum/subjects/class-templates
- [x] 6.2 Add mutations: update/delete/bulk-delete for years, curriculum versions, subjects, class templates
- [x] 6.3 Add `src/lib/schemas/academic-years-params.ts`, `academic-subjects-params.ts`, `academic-class-templates-params.ts` (parse/serialize, mirror `tenant-roles-params.ts`); subjects + templates carry filter ids

## 7. Web — Tahun Ajaran screen (rebuilt)

- [x] 7.1 Rebuild `years/page.tsx` on `DataTable` with multi-select, sortable headers, search, URL-synced pagination, per-row actions dropdown (Edit/Hapus), and bulk delete confirmed via `ConfirmDialog`
- [x] 7.2 Build the create/edit modal as a scrolling sectioned form: §Identitas (name, dates, status transition), §Kebijakan Nilai (upsert; disabled on create), §Versi Kurikulum (inline add/list/delete)
- [x] 7.3 Surface guard errors (`ACTIVE_YEAR_IMMUTABLE`, `YEAR_IN_USE`) via `getErrorMessage`

## 8. Web — Mata Pelajaran screen (new)

- [x] 8.1 Create `subjects/page.tsx`: cascading Tahun Ajaran ▾ + Versi Kurikulum ▾ filters (version depends on year, table gated on version), URL-synced
- [x] 8.2 `DataTable` (Nama/Kode/KKM), multi-select, per-row Edit/Hapus, bulk delete; create/edit Dialog; surface `SUBJECT_IN_USE`

## 9. Web — Template Kelas screen (rebuilt)

- [x] 9.1 Rebuild `class-templates/page.tsx` as `DataTable` filtered by Tahun Ajaran ▾ (URL-synced), multi-select, per-row Edit/Hapus, bulk delete, create/edit Dialog

## 10. Web — nav + removal

- [x] 10.1 Update `academicNav` in `academic-settings.tsx`: Tahun Ajaran, Mata Pelajaran, Template Kelas; remove Kebijakan Nilai and Kurikulum entries
- [x] 10.2 Delete `grading-policy/page.tsx` and `curriculum/page.tsx`; verify no dangling imports/links
- [x] 10.3 Add/extend Vitest specs for the rebuilt screens (table render, filter gating, modal sections)

## 11. Verify

- [x] 11.1 `cd apps/web && pnpm lint && pnpm test && pnpm build` (or repo equivalents) green
- [x] 11.2 Manual smoke: create year + policy + version, edit, delete guards, subjects filter cascade, template CRUD
