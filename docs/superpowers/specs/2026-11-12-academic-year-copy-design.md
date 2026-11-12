# Academic Year Copy Wizard — Design Spec

Date: 2026-11-12
Status: approved in brainstorming; awaiting written-spec review
Topic: copy a school's yearly setup from one academic year into a Draft year
Related: `docs/internal/08_sequences/02_Academic_Year_Initialization.md` (the
"clone previous year setup" flow this finally implements);
`docs/superpowers/backlog.md` entry "target year forces closing the source
year first" (resolved by §4).

## 1. Goal

Every new academic year an admin re-creates the same setup by hand: terms,
grade levels, classes, curriculum and subjects, the passing score, report
types and their weights. The maintainer hit this during manual promotion
testing: after creating 2026-2027 he had to rebuild six grade levels and six
classes one by one.

A wizard copies that setup from a chosen source year into a Draft target year
in one pass. Data that already exists in the target is skipped, never
overwritten, so the wizard can be run again safely and can resume after an
interruption.

**Done means:** an admin creates 2026-2027 (or opens an existing Draft year),
picks 2025-2026 as the source, keeps the default checklist, confirms the
shifted term dates, and ends with the same terms, grade levels, classes,
curriculum, subjects, passing score, report types and evaluation weights in
2026-2027 — no students, scores or report cards. Closing the browser halfway
and coming back shows a "Lanjutkan" banner that finishes the remaining parts.

### 1.1 Decisions from brainstorming

| # | Question | Decision |
|---|---|---|
| D1 | What is copied | Checklist; defaults below (§2) |
| D2 | Source year | Admin picks any year of the tenant; default is the most recent year by start date other than the target |
| D3 | UI | Multi-step wizard, full page with the step list on the side (layout B) |
| D4 | Entry points | "Tahun ajaran baru" (create + copy) and "Salin dari tahun lain" on an existing Draft year |
| D5 | Target constraints | Target must be `Draft`; existing data is skipped, never overwritten |
| D6 | Classes in Draft years | Allowed (manual and via copy); enrolling students still requires an `Active` year |
| D7 | Orchestration | The web calls one copy endpoint per service in order: academic-config → academic-ops → grading |
| D8 | Interrupted copy | Recorded as a copy run in academic-config; the year page shows a "Lanjutkan" banner that resumes it |

### 1.1a Calls made while writing the spec (not discussed; check these)

| # | Call | Why |
|---|---|---|
| C1 | academic-config returns a source→target **id map** (terms, grade levels, subjects) and stores it on the copy run; the web passes it to academic-ops and grading | academic-config emits no subject events today, so academic-ops cannot map subjects through a projection. An id map avoids a new event + projection + backfill. Each service still validates the ids it can (grade levels via `known_grade_level`, terms via `valid_term`) |
| C2 | Every copy endpoint supports `dry_run: true`, returning the would-be copied/skipped counts | Feeds the counts in wizard step 3 and the summary in step 5 without new read endpoints |
| C3 | Permission: the wizard and all copy / copy-run endpoints require the tenant admin role **and** `academic.config.write` | grading's `report-types/copy` already uses `require_admin`; academic-ops' `create_homeroom` checks no permission today (separate gap, listed in §8) |
| C4 | `copy_run_id` on the academic-ops and grading calls is an audit label only; those services do not read the run | Reading it would be a synchronous call to academic-config (§1.3) |
| C5 | "Batalkan" only stops the run; nothing is rolled back and there is no "undo copy" | Copied rows are ordinary data the admin can edit or delete with the existing screens; a target that already holds them is skipped on the next run |
| C6 | Shifted term dates are validated with the same rules as manual term creation; a shifted 29 February becomes 28 February | Reuses one rule set |

### 1.2 Non-goals

- Copying students, enrollments, scores, evaluations with scores, report
  cards, promotion runs or letters. Moving students is the promotion feature.
- Overwriting or merging into existing target data (no "overwrite" mode).
- Copying into an `Active`, `Closed` or `Archived` year.
- A server-side saga / background job. The browser drives the steps (D7).
- Cross-tenant copy or templates shared between schools.

### 1.3 Anti-goals

- A copy that silently half-applies inside one service. Each service step is
  one database transaction.
- A copy that changes the target year's status, or makes a half-copied year
  usable for enrollment.
- Synchronous service-to-service HTTP calls. Each service maps source rows to
  target rows through data it already owns or projects.

## 2. What can be copied

Grouped as the wizard shows them. "Default" is the initial checkbox state.
Counts come from the source year and are shown next to every item.

| Item | Default | Owner | Depends on |
|---|---|---|---|
| Semester (terms) | on | academic-config | — |
| Tingkat (grade levels) | on | academic-config | — |
| Kelas + kapasitas (class templates + homerooms) | on | academic-config + academic-ops | Tingkat |
| ↳ Wali kelas (homeroom teacher) | off | academic-ops | Kelas |
| Kurikulum, kelompok mapel, mata pelajaran | on | academic-config | — |
| Kebijakan nilai (passing score) | on | academic-config | — |
| Tipe rapor + sumber kenaikan | on | grading | Semester |
| ↳ Template evaluasi + bobot | on | grading | Tipe rapor |
| Penugasan guru (teaching assignments) | off | academic-ops | Kelas, Kurikulum |
| ↳ Jadwal pelajaran (timetable) | off | academic-ops | Penugasan |

A dependent item is disabled (unchecked, with its reason shown) while what it
depends on is unchecked **and** the target does not already contain that data.
Example: "Penugasan" stays enabled with "Kelas" unchecked if the target
already has classes.

Never copied: students, enrollments, family links, evaluations that hold
scores, grades, report cards, report subject scores, promotion data, letters,
attendance.

## 3. Matching rules ("already exists → skip")

Each copy step maps source rows to target rows by a natural key. A source row
whose key already exists in the target is skipped and counted as skipped. The
mapping of skipped rows is still used by later steps, so a class whose grade
level was skipped still links to the existing target grade level.

| Data | Natural key in the target year |
|---|---|
| Term | `name` (existing unique index) |
| Grade level | `code` |
| Class template | grade level (mapped by code) |
| Curriculum version | `name` |
| Subject group | `code`, else `name`, within the mapped curriculum version |
| Subject | `code`, else `name`, within the mapped curriculum version |
| Grading policy | one per year (existing unique index) |
| Homeroom | `name` |
| Teaching assignment | (teacher, mapped subject, mapped homeroom) — existing unique index |
| Timetable slot | (mapped homeroom, day, start time) |
| Report type | (mapped term, `code`) — existing unique index |
| Evaluation template | (mapped term, `code`) — existing unique index |
| Formula template weight | (mapped report type, mapped evaluation template) |

Term dates are shifted by the difference between the source and target year
start dates. The wizard previews the shifted dates (step 4) and the admin can
edit each one before running. Copied terms start as `Draft`.

Copied homerooms keep name, capacity and grade level (mapped by code). The
homeroom teacher is copied only when "Wali kelas" is checked; archived
teachers are skipped.

## 4. Academic-ops: classes in Draft years (D6)

Today `create_homeroom` rejects any year that is not `Active`
(`academic-ops-service/src/commands.rs`, `known_years.is_active`, error
`UNKNOWN_ACADEMIC_YEAR`). Change it to accept `Draft` or `Active` and still
reject `Closed` / `Archived` / unknown.

`enroll_student` today relies on the homeroom check for the year rule. It must
now check explicitly that the homeroom's year is `Active` and fail otherwise
with a new code `ACADEMIC_YEAR_NOT_ACTIVE` (409). Other year-scoped writes
that currently lean on "homerooms only exist in Active years" are audited in
the plan and get the same explicit check where enrolment-like behaviour
depends on it.

The backlog entry "target year forces closing the source year first" is
resolved: the target year's classes can be prepared while the current year is
still Active.

## 5. Copy endpoints

All three are `POST`, require `academic.config.write` (academic-config) or the
service's existing write permission for the copied data (academic-ops,
grading), take `tenant_id` from the JWT only, and are idempotent: running one
again copies nothing new and reports everything as skipped.

Request body (shared shape):

```json
{
  "source_academic_year_id": "uuid",
  "target_academic_year_id": "uuid",
  "copy_run_id": "uuid",
  "items": ["terms", "grade_levels", "classes", "homeroom_teachers",
            "curriculum", "grading_policy", "report_types",
            "evaluation_weights", "teaching_assignments", "timetable"]
}
```

Optional fields: `dry_run` (boolean, C2) and, for academic-ops and grading,
`id_map` (C1):

```json
"id_map": {
  "terms":        { "<source term id>": "<target term id>" },
  "grade_levels": { "<source grade level id>": "<target grade level id>" },
  "subjects":     { "<source subject id>": "<target subject id>" }
}
```

Each endpoint ignores items it does not own. Response:

```json
{ "data": { "results": [
  { "item": "grade_levels", "copied": 6, "skipped": 0 },
  { "item": "classes", "copied": 6, "skipped": 0 }
] }, "meta": {} }
```

Errors: `ACADEMIC_YEAR_NOT_DRAFT` (409) when the target is not Draft;
`VALIDATION_ERROR` when source = target or a year is unknown;
`COPY_DEPENDENCY_NOT_READY` (409, retryable) when the service's projection
does not yet contain the target-year data it needs from an earlier step.

### 5.1 academic-config — `POST /api/v1/academic-config/academic-years/copy`

Copies terms, grade levels, class templates, curriculum versions, subject
groups, subjects and the grading policy in one transaction. Emits the same
events the manual create endpoints emit (`academic_term.created`,
`grade_level.created`, `grading_policy.configured`, …) through the outbox, so
downstream projections fill exactly as if the admin had typed everything.
Term date overrides from wizard step 4 travel in an optional
`term_dates: [{ "source_term_id", "start_date", "end_date" }]`.
The response adds the `id_map` (C1) covering every mapped term, grade level
and subject — copied or skipped — and the same map is stored on the copy run.

### 5.2 academic-ops — `POST /api/v1/academic-ops/academic-years/copy`

Copies homerooms (+ homeroom teacher), teaching assignments and timetable
slots in one transaction. Grade levels and subjects are mapped with the
`id_map` from academic-config (C1). A target grade level id must already be
present in `known_grade_level` for the target year; if any is missing the
call returns `COPY_DEPENDENCY_NOT_READY` and copies nothing. Subject ids are
taken from the map as-is, the same trust level teaching assignments have
today. Emits `homeroom.created` and `teacher.assigned` like the manual
endpoints.

### 5.3 grading — `POST /api/v1/grading/academic-years/copy`

Copies report types (including `is_promotion_source`), evaluation templates
and formula template weights in one transaction. Terms are mapped with the
`id_map` (C1); every target term must already be in `valid_term`, otherwise
the call returns `COPY_DEPENDENCY_NOT_READY` and copies nothing. Emits
`report_type.promotion_source_changed` for copied promotion-source report
types so academic-ops' `known_report_type` stays correct. Reuses the existing
`report-types/copy` logic where it fits.

## 6. Copy run record (D8)

New table in academic-config, `academic_year_copy_run`:

| Column | Notes |
|---|---|
| `copy_run_id` | PK |
| `tenant_id` | |
| `source_academic_year_id`, `target_academic_year_id` | |
| `items` | `TEXT[]`, the checklist as chosen |
| `term_dates` | `JSONB`, step-4 overrides, nullable |
| `status` | `in_progress`, `completed`, `cancelled` |
| `id_map` | `JSONB`, written by the academic-config step (C1) |
| `config_result`, `ops_result`, `grading_result` | `JSONB` per-step results, null until that step finished |
| `created_by`, `created_at`, `updated_at` | |

At most one `in_progress` run per target year (partial unique index).

Endpoints (academic-config, `academic.config.write`):

- `POST /academic-years/:id/copy-runs` — start a run (target = `:id`); 409
  if one is already in progress.
- `GET /academic-years/:id/copy-runs/current` — the in-progress run or 404.
- `PATCH /copy-runs/:copy_run_id` — the web records a step result
  (`{ "step": "ops", "result": [...] }`), or sets `status` to `completed` /
  `cancelled`.

The academic-config copy endpoint (§5.1) writes `config_result` itself in the
same transaction as the copy. The web records `ops_result` and
`grading_result` after those calls succeed and marks the run `completed`
after the last one. Cancelling keeps everything already copied.

## 7. Web wizard

Route `/settings/academic/years/copy` (new year) and
`/settings/academic/years/:id/copy` (existing Draft year). Full page, step
list on the left with the source and target year always visible, content on
the right (layout B). shadcn/ui only, TanStack Query for every call, error
messages from `@/lib/errors/messages`, following `apps/web/CONVENTIONS.md`.

1. **Identitas tahun** — name, start date, end date. Skipped when opened from
   an existing Draft year. Creating the year happens when leaving this step.
2. **Tahun sumber** — select of the tenant's other years, default per D2, plus
   "Mulai kosong" (ends the wizard; just the empty year).
3. **Data yang disalin** — the §2 checklist with counts (from `dry_run`
   calls, C2) and dependency locking.
4. **Tanggal semester** — table of copied terms with shifted dates, editable.
   Skipped when "Semester" is unchecked.
5. **Ringkasan** — what will be created; "Mulai salin" starts the run and
   calls config → ops → grading in order, showing each part's progress and its
   "X disalin, Y dilewati" result. `COPY_DEPENDENCY_NOT_READY` is retried
   automatically with backoff for up to about a minute, then shown as a
   retryable error.

Entry points: the "Tahun ajaran baru" button on the Tahun Ajaran page opens
the wizard at step 1; an existing Draft year's row menu offers "Salin dari
tahun lain" (step 2). When `copy-runs/current` returns a run, the Tahun Ajaran
page shows a banner "Penyalinan dari <source> belum selesai (<n> dari 3
bagian)" with **Lanjutkan** (opens the wizard at step 5 with the stored
choices and runs the remaining parts) and **Batalkan**.

## 8. Docs to update

- `docs/internal/08_sequences/02_Academic_Year_Initialization.md` — replace
  the placeholder flow with the web-orchestrated copy.
- `docs/internal/11_integration_contracts/apis/` — the three copy endpoints
  and the copy-run endpoints.
- `docs/internal/11_integration_contracts/events/` — any new subject events
  (§5.2).
- `docs/internal/10_data_design/` academic-config ERD — `academic_year_copy_run`.
- `docs/superpowers/backlog.md` — close the "closing the source year first"
  entry; add "academic-ops `create_homeroom` / teaching-assignment writes check
  no permission" as a separate security gap (found while writing this spec;
  not fixed here beyond the new copy endpoint).

## 9. Left to the builder

- Exact migration numbers and file names per service.
- Whether the three copy endpoints share code with existing create commands or
  insert directly (events must match the manual endpoints either way).
- Retry/backoff numbers for `COPY_DEPENDENCY_NOT_READY`. If it keeps failing
  (e.g. the event relay is down) the wizard shows the error with "Coba lagi";
  the run stays resumable from the banner.
- Which other year-scoped writes need the explicit `Active` check (§4); there
  is no attendance module yet.
- Layout details of each wizard step within shadcn/ui.
