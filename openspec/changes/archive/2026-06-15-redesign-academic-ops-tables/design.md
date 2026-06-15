# Design — redesign-academic-ops-tables

## Screen pattern (all four)

Every operational screen follows the users/roles shape:

```
┌ /students ────────────────────────────────────────────┐
│ Siswa                                  [Impor ▾] [+ Tambah]│
│ ┌────────────────────────────────────────────────────┐│
│ │ [search……]                                          ││ ← debounced, URL-synced
│ ├────────────────────────────────────────────────────┤│
│ │ BulkActionBar (n dipilih) [Hapus]   (when selected) ││
│ ├────────────────────────────────────────────────────┤│
│ │ □ NIS ▴  Nama       Gender   Tgl Lahir   Aksi ⋯     ││
│ ├────────────────────────────────────────────────────┤│
│ │ Halaman 1 dari 4 · 80 siswa     [Prev] [Next]       ││
│ └────────────────────────────────────────────────────┘│
│ Dialog(create/edit)  ConfirmDialog(delete)  ImportDialog│
└─────────────────────────────────────────────────────────┘
```

`opsNav` (`academic-ops-page.tsx`) drops the **Import** entry; the remaining four
tabs stay. The shared `OpsShell` (auth, entitlement gate, sidebar) is preserved;
only the per-panel bodies are rebuilt.

## Import relocation

```
BEFORE                          AFTER
──────                          ─────
/import (standalone page)       /students  [Impor ▾] → ImportDialog (siswa)
  ├ ImportBox siswa             /teachers  [Impor ▾] → ImportDialog (guru)
  └ ImportBox guru              /import REMOVED, opsNav entry removed
```

`ImportDialog` wraps the existing import mutation flow (`useImportStudents` /
`useImportTeachers`), the template-download link, and the row-level error report
(`extractImportRows`) that `ImportPanel` already implements — so the validation
contract and error rendering are reused verbatim, just relocated into a modal and
fed by `FileDropzone`.

## FileDropzone (reusable, `react-dropzone`)

```
┌ components/ui/file-dropzone.tsx ───────────────────────┐
│  ┌──────────────────────────────────────────────────┐ │
│  │   ⬆  Tarik file ke sini atau klik untuk pilih      │ │
│  │      .xlsx, .xls, .ods — maks 1 file               │ │
│  └──────────────────────────────────────────────────┘ │
│  ▸ when a file is chosen: "students.xlsx · 24 KB  ✕"   │
└─────────────────────────────────────────────────────────┘
```

Props (kept minimal/generic so it is not import-specific):
`value: File | null`, `onChange(file: File | null)`, `accept`, `maxSize?`,
`disabled?`. Drag-over and rejection states use shadcn tokens
(`border-dashed`, `bg-muted/30`, `border-destructive` on reject). Rejections
(wrong type/too big) surface inline text. Built on `useDropzone({ accept,
maxFiles: 1 })`.

## Teacher ↔ account link (moved to row dropdown)

The link is **not** dropped — it moves from an inline cell `QuerySelect` to a
per-row action:

```
Akun column:  ✓ Terhubung   |   — Belum terhubung   (badge)
Row dropdown:  Edit · Hubungkan akun · Hapus
  "Hubungkan akun" → modal: QuerySelect of teacher-role users → useLinkTeacherAccount
```

Why it matters (carried into the spec as rationale): teacher master data
(`teacher_id`, NIP) is separate from login accounts (`user_id`). Teachers can be
imported/created before they have a login; `teaching_assignment` and `grade`
reference `teacher_id`, auth references `user_id`. The link bridges them so a
teacher can log in to see classes and grade. The **Akun** column is the
at-a-glance readiness signal.

## Homeroom roster (row action → modal)

Per the interview decision, master-detail via modal (not a separate page):

```
Row dropdown: Edit · Roster · Hapus
"Roster" → Dialog:
  ┌ Roster — Kelas 7A (2026/2027) ─────────────┐
  │ [+ Enroll siswa ▾]                          │
  │ □ Nama            Status      Aksi          │
  │ □ Budi Santoso    active     [unenroll]     │
  └─────────────────────────────────────────────┘
```

Enroll uses `useEnrollStudent(homeroomId)`; unenroll uses the existing
`DELETE .../enrollments`. The roster table reuses `DataTable` (client-side is
fine here — a roster is bounded by class capacity, so no server pagination
needed).

## Teaching assignments (filters + modal chained form)

```
[Tahun ▾] [Kurikulum ▾] [Kelas ▾]              [+ Tambah Penugasan]
□ Guru          Mapel        Kelas       Tahun        Aksi
□ Budi          Matematika   7A          2026/2027    [hapus]

[+ Tambah] → Dialog with the existing chained form
            (tahun→kurikulum→kelas→guru→mapel)
```

The list is server-driven once the backend list endpoint is reworked; filters map
to query params and the URL. Per-row delete hits the new assignment `DELETE`.

## Backend list rework (mirror IAM)

Identical shape to the config proposal: each `list(tenant_id) -> Vec<_>` becomes
`QueryBuilder` + search filter + whitelisted `ORDER BY` + `LIMIT/OFFSET` +
`count_*`, and the handler returns `{ data, meta: { page, page_size, total } }`.
Sort keys are parsed/whitelisted server-side (`INVALID_SORT` on unknown).

## Delete guards (referential integrity)

| Resource | Delete allowed when | Reject code |
|---|---|---|
| Student | no `active` enrollment | `STUDENT_ENROLLED` |
| Teacher | no teaching assignments reference it | `TEACHER_ASSIGNED` |
| Homeroom | roster is empty (no active enrollments) | `HOMEROOM_NOT_EMPTY` |
| Teaching assignment | always | — |

Bulk delete is **all-or-nothing** (pre-validate all ids, reject whole request on
first violation), matching `BulkDeleteRoles`.

## Decisions & open questions

1. **Roster table is client-side.** Bounded by class capacity, so no server
   pagination; the four main screens are server-driven.
2. **Teacher delete vs. linked account.** Deleting a teacher row deletes master
   data only; it does **not** delete the linked login user (that is an IAM
   concern). If assignments exist, `TEACHER_ASSIGNED` blocks the delete.
3. **`react-dropzone` dependency.** Chosen over a hand-rolled drag handler for
   correct file-type/size rejection and accessibility; pinned to an exact version
   in `package.json`.
4. **No event-contract changes.** Deletes add `*.deleted` events only if a
   downstream consumer needs them; none do today.
