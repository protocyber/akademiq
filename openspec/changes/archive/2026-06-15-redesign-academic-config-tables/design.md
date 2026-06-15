# Design — redesign-academic-config-tables

## Information architecture

The academic year is the parent of all academic-config data. The four old tabs
collapse to three, with grading policy and curriculum versions folded into the
year modal:

```
BEFORE (4 tabs)                      AFTER (3 tabs)
──────────────                       ─────────────
years            ──┐                 years          ← DATATABLE (parent)
curriculum     ────┤                   modal §Identitas / §Kebijakan Nilai
grading-policy ──┐ │                         §Versi Kurikulum (inline list)
class-templates  │ │                 subjects       ← DATATABLE, filter Year▾ Versi▾
                 │ └─→ folded into    class-templates← DATATABLE, filter Year▾
   grading-policy┘     year modal     (grading-policy page REMOVED)
   + curriculum
```

### Nav (`academic-settings.tsx`)

`academicNav` becomes:

```
/settings/academic/years            → "Tahun Ajaran"
/settings/academic/subjects         → "Mata Pelajaran"   (new)
/settings/academic/class-templates  → "Template Kelas"
                                      ("Kebijakan Nilai" removed)
                                      ("Kurikulum" removed — folded into year modal)
```

## Why subjects are a separate table, not in the year modal

Subjects hang off a curriculum version (`year → curriculum_version → subject`).
Folding versions into the year modal is fine (one level), but nesting subjects
would make the modal three levels deep — fighting the "clean like users/roles"
goal where a modal holds one focused form. Instead subjects get a dedicated table
with two cascading filter dropdowns:

```
┌ /settings/academic/subjects ──────────────────────────┐
│ [Tahun Ajaran ▾]  [Versi Kurikulum ▾]  [+ Tambah Mapel]│  ← versi options depend on year
│ ┌──────────────────────────────────────────────────┐  │
│ │ □ Nama ▴   Kode      KKM     Aksi                  │  │
│ │ □ Matematika  MTK      75    ⋯                     │  │
│ └──────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────┘
```

The version filter is disabled until a year is chosen. The subjects query is
`enabled` only when a curriculum version is selected (same gating the current
`useSubjects(curriculumVersionId)` uses).

## Year create/edit modal (scrolling sectioned form)

Per the interview decision, **not** tabbed — one scrolling form with sections:

```
┌ Edit Tahun Ajaran 2026/2027 ──────────────────────────┐
│ § Identitas                                            │
│   Nama [____]  Mulai [date]  Selesai [date]            │
│   Status: Active   [Ubah Status ▾]  (lifecycle select) │
│                                                        │
│ § Kebijakan Nilai                                      │
│   Min. kelulusan [75]   Skala [0-100 ▾]                │
│                                                        │
│ § Versi Kurikulum                                      │
│   • Kurikulum Merdeka            [hapus]               │
│   • K13                          [hapus]               │
│   [+ Nama versi ___] [Tambah]                          │
│                                          [Simpan]      │
└────────────────────────────────────────────────────────┘
```

Section persistence semantics:
- **Identitas** writes via create (`POST`) or the new year `PATCH`/status
  endpoints.
- **Kebijakan Nilai** writes via the existing `PUT .../grading-policy` upsert;
  on the create flow it is saved after the year exists (so the section is
  read-only/disabled until the year is created, or the create is a two-step save
  — see Decisions).
- **Versi Kurikulum** add → `POST .../curriculum-versions`; row delete → the new
  curriculum-version `DELETE`. Each acts immediately (no staged diff) to avoid a
  complex nested form state.

## Backend list rework (mirror IAM)

Each list endpoint moves from `list(tenant_id) -> Vec<_>` to the IAM shape:

```
http.rs:   struct <Resource>Query { search, sort, page, page_size }
              → into_params(tenant_id) -> List<Resource>Params
           handler returns json!({ "data": rows, "meta": { page, page_size, total } })
queries.rs: List<Resource>Params { tenant_id, search, sort, page, page_size }
            Paginated<Resource> { data, page, page_size, total }
repo.rs:    QueryBuilder + push filters + ORDER BY sort.sql() + LIMIT/OFFSET
            + count_<resource>(params) -> i64
```

Sort whitelist is parsed server-side (reject unknown → `INVALID_SORT`), exactly
like `TenantUserSort::parse`.

## Delete guards (referential integrity)

| Resource | Delete allowed when | Reject code |
|---|---|---|
| Academic year | not `Active`; no homerooms/teaching-assignments reference it | `YEAR_IN_USE` / `ACTIVE_YEAR_IMMUTABLE` |
| Curriculum version | has no subjects (or cascade — see Decisions) | `CURRICULUM_IN_USE` |
| Subject | not referenced by a teaching assignment | `SUBJECT_IN_USE` |
| Class template | always (advisory only) | — |

Bulk delete is **all-or-nothing**, pre-validating every id and rejecting the
whole request on the first violation — identical to the `BulkDeleteRoles`
pattern (`iam-service/commands.rs`).

## URL-synced params (web)

One `*-params.ts` per table, copying `tenant-roles-params.ts`:
`parseAcademicYearsParams` / `serializeAcademicYearsParams`, etc. Subjects and
class-templates params additionally carry their filter ids
(`academic_year_id`, `curriculum_version_id`) so refresh/bookmark reproduces the
filtered view.

## Decisions & open questions

1. **Grading policy on create.** A grading policy needs an existing
   `academic_year_id`. Decision: on **create**, the Kebijakan Nilai section is
   disabled with a hint ("tersedia setelah tahun ajaran dibuat"); it becomes
   editable on **edit**. Avoids a two-phase transactional save across services.
2. **Curriculum version delete with subjects.** Default to **guarded**
   (`CURRICULUM_IN_USE` if it has subjects) rather than cascade, so subjects are
   never silently destroyed; admin clears subjects on the subjects table first.
3. **Active-year delete.** Disallow deleting an `Active` year; require
   transitioning it out of Active first. Keeps the one-active-year invariant and
   downstream projections consistent.
4. **Cross-service delete guards via event-sourced projection.** The
   `YEAR_IN_USE` and `SUBJECT_IN_USE` guards need homeroom / teaching-assignment
   data, which lives in `academic_ops_db` (a separate service's database).
   Rather than add a synchronous HTTP check between services, academic-config
   consumes academic-ops events into local `year_usage_ref` /
   `subject_usage_ref` projection tables (migration `V2__usage_projection.sql`)
   and the guards query those. This revises the earlier "no new events" stance:
   the change now **adds** a `homeroom.created` event (academic-ops
   `create_homeroom` previously emitted nothing) and extends the existing
   `teacher.assigned` payload with `assignment_id` so each projection row keys
   idempotently. No delete events are needed because homerooms and teaching
   assignments are not deleted today; the projection only ever grows.

## Deferred follow-up — global academic-year selector

A requested UI improvement (`.agent/prompts/2026-06-09/improvement.md`, item #5)
is a **global academic-year selector in the app header**, so users pick the year
once instead of re-picking it on every page that has a local `YearPicker`
(grading, report-cards, academic config/ops, teaching-assignments).

This is **intentionally deferred until this change lands.** This change makes the
academic year the **parent entity** of academic configuration; a global
year-context selector should be built on top of that finalized model, not
alongside it, to avoid reworking the local `YearPicker` usages twice. Sequencing:
finish `redesign-academic-config-tables` → then introduce the global year context
as its own change that replaces the per-page pickers.

Tracking note only — **no work on the global selector is in scope here.**
