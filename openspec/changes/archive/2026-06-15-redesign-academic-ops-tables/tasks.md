# Tasks — redesign-academic-ops-tables

Work is ordered **per resource, end-to-end** (backend → web). Backend mirrors the
IAM `QueryBuilder`/count + all-or-nothing bulk-delete patterns. Reusable upload
components (§7) land before the screens that consume them (§3, §4).

## 1. Students — backend

- [x] 1.1 Rework `StudentRepo::list` (`academic-ops-service/src/repo.rs:34`) into a `QueryBuilder` with case-insensitive search (nis/full_name), whitelisted `ORDER BY` (nis/full_name/birth_date), `LIMIT/OFFSET`; add `count_students(params)`
- [x] 1.2 Add `ListStudentsParams` + `PaginatedStudents` in `queries.rs`; add `StudentSort::parse` rejecting unknown → `INVALID_SORT`
- [x] 1.3 Add `StudentsQuery` extractor; update `list_students` (`http.rs`) to return `{ data, meta }`
- [x] 1.4 Add `DELETE /students/:id` + bulk; command guards `STUDENT_ENROLLED` (active enrollment exists)
- [x] 1.5 Integration tests (paginated list, `INVALID_SORT`, delete guarded/allowed, bulk all-or-nothing) + `make test`

## 2. Teachers — backend

- [x] 2.1 Rework `TeacherRepo::list` into paginated `{ data, meta }` with search (nip/full_name) + sort + count
- [x] 2.2 Add `PATCH /teachers/:id` (nip, full_name); `DELETE` + bulk guarding `TEACHER_ASSIGNED`; delete MUST NOT remove the linked login user
- [x] 2.3 Integration tests (patch, delete guarded/allowed, linked-user untouched, bulk all-or-nothing) + `make test`

## 3. Homerooms — backend

- [x] 3.1 Rework `HomeroomRepo::list` into paginated `{ data, meta }` with search (name/grade_level) + sort + count
- [x] 3.2 Add `DELETE /homerooms/:id` + bulk guarding `HOMEROOM_NOT_EMPTY` (active enrollments exist)
- [x] 3.3 Integration tests + `make test`

## 4. Teaching assignments — backend

- [x] 4.1 Rework `list_for_homeroom`/assignment list into paginated `{ data, meta }` with filters (year/curriculum/homeroom) + sort + count
- [x] 4.2 Add `DELETE /teaching-assignments/:id` + bulk (always deletable for tenant-owned rows)
- [x] 4.3 Integration tests + `make test`

## 5. Backend — contract docs

- [x] 5.1 Document the new query params + `{ meta }`, teacher PATCH, and the DELETE/bulk-delete endpoints (guard codes `STUDENT_ENROLLED`, `TEACHER_ASSIGNED`, `HOMEROOM_NOT_EMPTY`, `INVALID_SORT`) in `docs/internal/11_integration_contracts/apis/academic-ops-service-api.md`

## 6. Web — query/mutation layer + params schemas

- [x] 6.1 Extend `use-academic-ops.ts` queries: accept params, type `{ data, meta }` for students/teachers/homerooms/assignments
- [x] 6.2 Add mutations: teacher update; delete + bulk-delete for students, teachers, homerooms, assignments
- [x] 6.3 Add `src/lib/schemas/students-params.ts`, `teachers-params.ts`, `homerooms-params.ts`, `teaching-assignments-params.ts` (parse/serialize, mirror `tenant-users-params.ts`)

## 7. Web — reusable upload components

- [x] 7.1 Add `react-dropzone` to `apps/web/package.json` (pinned exact version)
- [x] 7.2 Create `src/components/ui/file-dropzone.tsx`: drag-and-drop + click, `accept`/`maxSize`, rejection feedback, selected-file preview, shadcn styling; `value/onChange` API
- [x] 7.3 Create `ImportDialog` (download-template link + `FileDropzone` + import action + row-error report), reusing `extractImportRows`
- [x] 7.4 Vitest specs for `FileDropzone` (accept/reject, onChange) and `ImportDialog` (success + row errors)

## 8. Web — Students screen (rebuilt)

- [x] 8.1 Rebuild `app/students` on `DataTable` (NIS, Nama, Gender, Tgl Lahir) with multi-select, sortable headers, search, URL-synced pagination, per-row Edit/Hapus, bulk delete via `ConfirmDialog`
- [x] 8.2 Create/edit `Dialog` modal; header **[Impor ▾]** opens `ImportDialog` (siswa); surface `STUDENT_ENROLLED`

## 9. Web — Teachers screen (rebuilt)

- [x] 9.1 Rebuild `app/teachers` on `DataTable` (NIP, Nama, **Akun** badge) with multi-select, search, sort, pagination, bulk delete
- [x] 9.2 Per-row dropdown: Edit · **Hubungkan akun** (modal user-picker via `useLinkTeacherAccount`) · Hapus; header **[Impor ▾]** opens `ImportDialog` (guru); surface `TEACHER_ASSIGNED`

## 10. Web — Homerooms screen (rebuilt)

- [x] 10.1 Rebuild `app/homerooms` on `DataTable` (Nama, Tingkat, Tahun, Kapasitas) with multi-select, search, sort, pagination, create/edit `Dialog`, bulk delete (`HOMEROOM_NOT_EMPTY`)
- [x] 10.2 Per-row **Roster** action → modal with roster `DataTable` + enroll (`useEnrollStudent`) / unenroll

## 11. Web — Teaching assignments screen (rebuilt)

- [x] 11.1 Rebuild `app/teaching-assignments` on `DataTable` (Guru, Mapel, Kelas, Tahun) with filter dropdowns (Tahun/Kurikulum/Kelas, URL-synced) and per-row delete
- [x] 11.2 **[Tambah Penugasan]** opens the chained form (tahun→kurikulum→kelas→guru→mapel) in a `Dialog`

## 12. Web — import removal + ops shell

- [x] 12.1 Remove `app/import`; drop the Import entry from `opsNav` in `academic-ops-page.tsx`; verify no dangling links
- [x] 12.2 Refactor/trim `academic-ops-page.tsx` panels superseded by the rebuilt pages

## 13. Verify

- [x] 13.1 `cd apps/web && pnpm lint && pnpm test && pnpm build` (or repo equivalents) green
- [ ] 13.2 Manual smoke: students CRUD + import, teachers CRUD + link + import, homeroom roster enroll/unenroll, assignment filter/create/delete, `/import` 404
