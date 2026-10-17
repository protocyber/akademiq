# Design Spec: Promotion UI (Plan 3d)

Date: 2026-10-12
Topic: the `/promotion` web flow for promotion runs, the homeroom ↔ grade level link, and the read fields the flow needs from academic-ops
Status: approved (design) — ready for `writing-plans`
Parent spec: `docs/superpowers/specs/2026-09-23-promotion-design.md` §7
Builds on: Plan 3b (evaluation, `2026-09-26-promotion-evaluation-design.md`) and
Plan 3c (execution, `2026-09-29-promotion-execution-design.md`)
API contract: `docs/internal/11_integration_contracts/apis/promotion-service-api.md`

---

## 1. Why this plan exists

The backend now runs the whole promotion cycle: evaluate, override, submit,
approve, set targets, execute, and turn graduates into alumni. Nobody can use
it without calling the API by hand. This plan adds the web screens, so a
school admin and principal can run promotion end to end in the browser.

Done means: on a seeded tenant, an admin creates a run, overrides a decision,
submits; the principal approves; the admin picks the target year, fills target
homerooms per class, sees placement against capacity, and executes — without
leaving the web app. That includes linking homerooms to grade levels (§3.0):
without it no real tenant can evaluate or place anyone, because nothing in the
product sets `homeroom.grade_level_id` today (in dev data 6 of 6 homerooms are
unlinked).

### 1.1 What this plan deliberately does NOT do

- **Printing** — SK Kenaikan Kelas, Surat Keterangan Lulus, the principal's
  name/NIP and letter numbers. Moved to **Plan 3e** (decided during this
  brainstorm: the print documents have their own data gaps).
- Undo of an executed run (not planned, spec 3c §8).
- Automatic class placement (rejected in the parent spec).
- The attendance criterion (waits for A2); it is shown disabled.
- Excel export, e2e tests (§7.3).

### 1.2 Deviations from the parent spec

| Parent spec §7 says | This plan does | Why |
|---|---|---|
| feature code `promotion` | `academic_ops` | Plan 3b reused the `academic_ops` entitlement; there is no `promotion` gate in code. |
| sidebar `permissionCode: "promotion.manage"` | visible to `promotion.manage` **or** `promotion.approve` | The principal holds only `promotion.approve` and must reach the page to approve. |
| "Panel pemetaan homeroom tujuan" | per-class defaults plus per-student correction (§5) | Plan 3c replaced the homeroom map with per-decision targets. |

---

## 2. Decisions

| # | Question | Decision |
|---|---|---|
| 1 | Scope split | **3d** = UI flow + decision/homeroom read fields; **3e** = printing |
| 1b | Linking homerooms to grade levels | **In 3d, first task** (§3.0) — found while planning; 3d's "done" is unreachable without it |
| 2 | Run detail structure | **One status-driven page** with tabs, not a per-stage wizard |
| 3 | Filling target homerooms | **Per source class default + per-student correction**, saved in one PATCH |
| 4 | Execute confirmation | **Summary dialog + typed confirmation** (target year name) |
| 5 | Data the UI needs | **Extend the backend read shapes**; no client-side joins |
| — | Placement tab state | **Local draft + one PATCH** on Save |

---

## 3. Backend (academic-ops-service)

### 3.0 Homerooms carry a grade level link

Today `homeroom.grade_level_id` (V15) is only ever set by V15's one-time
backfill; `POST` / `PATCH /homerooms` accept only the free-text `grade_level`.
Plan 3b deferred the reconciliation as "a human decision" (3b spec §7); this
gives the human the tool.

- `POST /homerooms` and `PATCH /homerooms/:id` accept an optional
  `grade_level_id` (uuid or null).
- When present it must be a `known_grade_level` row of the same tenant **and**
  the homeroom's academic year; otherwise `400 VALIDATION_ERROR` on field
  `grade_level_id`: `grade level not found in this academic year`.
- When a grade level is set, the stored text `grade_level` is set to that
  level's `code`, so existing screens, search and sort keep working. The
  request's `grade_level` text is then ignored, and it may be omitted.
- When `grade_level_id` is absent, behaviour is unchanged (text required, link
  untouched). `null` on PATCH clears the link and keeps the text.
- No migration: the column exists. No FK (V15's reason stands: the projection
  is eventually consistent).

Web, homeroom form (`homerooms-screen.tsx`): the free-text "Tingkat" input is
replaced by a select of the year's grade levels (`useGradeLevels(yearId)`,
label `label (code)`), sending `grade_level_id`. If the year has no grade
levels yet, the select is empty with a link to Pengaturan → Akademik → Tingkat
Kelas. The homeroom table shows a badge "Belum tertaut" for homerooms whose
`grade_level_id` is null, so old homerooms can be fixed via Edit.

Read fields used by the rest of this plan follow.

### 3.0.1 Tests

- Create with a valid `grade_level_id` stores the link and `grade_level` =
  the level's code.
- Create/patch with a grade level of another year, or of another tenant →
  `400` on `grade_level_id`; nothing written.
- Patch with `grade_level_id: null` clears the link.
- Create without `grade_level_id` behaves as before.

## 3a. Backend: read fields

Additive fields only. No migration, no new endpoint, no new error code, no
event.

### 3.1 Decision shape

`GET /promotion-runs/:run_id/decisions` and the `PATCH .../decisions/:id`
override response gain:

| Field | Type | Source |
|---|---|---|
| `full_name` | string | `student.full_name` |
| `nis` | string | `student.nis` |
| `homeroom_name` | string | source `homeroom.name` |
| `source_ordinal` | integer or null | `known_grade_level.ordinal` of the source homeroom's `grade_level_id`; null when unlinked |

Joined on `(tenant_id, student_id)` and `(tenant_id, homeroom_id)` with every
join filtered by `tenant_id`. They read the `student` and `homeroom` rows, not
enrollments, so they stay filled after execution, when the source enrollments
are `promoted` and the students have left the source roster.

Ordering stays `homeroom_id, student_id` (the web groups and sorts by name).

### 3.2 Homeroom shape

`GET /homerooms` (list) gains:

| Field | Type | Source |
|---|---|---|
| `grade_level_id` | uuid or null | `homeroom.grade_level_id` (V15) |
| `ordinal` | integer or null | `known_grade_level.ordinal`; null when unlinked or the link dangles |

The web filters target-homeroom dropdowns with the same ordinal the backend
validates against, so the two cannot disagree.

`GET /homerooms` also accepts an optional `academic_year_id` filter (added
while planning): the existing dropdown hook reads one page of at most 100
homerooms across every year, which silently truncates for a tenant with a few
years of history. The placement tab and the homeroom form read one year.

### 3.3 Backend tests

- Decisions list carries `full_name`, `nis`, `homeroom_name`, `source_ordinal`,
  and still carries them after the run is executed.
- `source_ordinal` is null for a decision whose source homeroom lost its grade
  level.
- Homeroom list carries `grade_level_id` and `ordinal`; both null when
  unlinked.
- Another tenant's student/homeroom/grade-level rows never leak through a join
  (seed same ids' neighbours in a second tenant).

---

## 4. Web: routes, access, page frame

### 4.1 Routes

- `/promotion` — academic-year picker (defaults to the `Active` year) and the
  year's runs: status badge, decision counts, created date, link to detail.
  "Buat evaluasi" opens the criteria dialog (§4.4); shown only with
  `promotion.manage`. When the year already has an open run (status other
  than `executed`), the button is replaced by a link to it.
- `/promotion/[runId]` — run detail.

### 4.2 Sidebar and guards

- New sidebar entry "Kenaikan Kelas" in the academic group, `featureCode:
  "academic_ops"`, visible when the user holds `promotion.manage` **or**
  `promotion.approve`.
- `sidebar-layout.tsx` visibility gains a variant
  `{ kind: "moduleAndAnyPermission"; featureCode; permissionCodes: string[] }`.
- Both routes are guarded the same way (module + any of the two permissions);
  a user without either is redirected like other guarded pages.

### 4.3 Detail page frame

- **Header**: academic year name, status badge, stage indicator
  (Draft → Diajukan → Disetujui → Dieksekusi), created by / approved by /
  executed by with dates.
- **Summary card**: counts promote / retain / graduate, overridden count,
  KKM, criteria.
- **Action bar**, by status and permission:

| Status | Permission | Actions |
|---|---|---|
| `draft` | manage | Evaluasi ulang, Ajukan |
| `submitted` | approve | Setujui, Kembalikan |
| `approved` | manage | Eksekusi (§5.4) |
| `executed` | — | none; page is read-only |

- **Tabs**: Keputusan and Tidak bisa dievaluasi always; Penempatan from
  `approved` on (read-only once `executed`).
- `PROMOTION_SELF_APPROVAL` on approve is shown with its own message.

### 4.4 Criteria dialog (create and re-evaluate)

Zod + React Hook Form; fields `min_average` (0–100, optional),
`max_subjects_below_kkm` (integer ≥ 0, optional), `min_attendance_percent`
shown disabled with "belum tersedia". Field keys match the backend.

- Create: `POST /promotion-runs`; `PROMOTION_RUN_EXISTS` → message plus a link
  to the existing run; precondition failures (`academic_year`, `grade_levels`,
  `report_type`, `homerooms`, `grading_policy`) shown as a grouped alert.
- Re-evaluate: prefilled with current criteria; warns "N keputusan yang
  di-override akan hilang" (N = run detail `overridden`); after success a toast
  reports `discarded_overrides`.

---

## 5. Web: tabs

### 5.1 Keputusan

- Second-level tabs per source homeroom, ordered by `source_ordinal` then
  `homeroom_name`, each with its student count. One fetch of all decisions,
  grouped on the client.
- Columns: NIS, name, average, subjects below KKM, recommendation, result
  (badge "Override" when it differs), reason; after execution also the target
  homeroom.
- Filters: result, overridden only, search by name/NIS.
- **Override** (draft + manage): row button "Ubah" opens a dialog — result
  radio, reason (required, ≥ 10 chars trimmed, unless result equals the
  recommendation), the student's metrics. Server field errors map to
  `result` / `reason`. `409` → alert and refetch.

### 5.2 Tidak bisa dievaluasi

Students in `cannot_evaluate`: name, NIS, homeroom, and the explanation
"belum ada rapor terbit pada tipe rapor sumber kenaikan". Names come from the
existing student list endpoint, filtered on the client (the list is short).

### 5.3 Penempatan (`approved` and later)

**Step 1 — target year.** Select from the tenant's years, excluding the
source year and `Closed` / `Archived` ones; `PUT .../target`. When decisions
already have targets and the year changes, confirm first ("N tujuan yang sudah
diisi akan dikosongkan"); toast `cleared_targets` afterwards. A `400` on
`target_academic_year_id` is listed under the picker.

**Step 2 — target homerooms** (enabled once a target year is saved). One row
per source homeroom:

- "Naik ke" — homerooms of the target year with `ordinal = source_ordinal + 1`;
  "Tinggal di" — `ordinal = source_ordinal`. A dropdown is hidden when that
  class has no student with that result.
- Choosing a class default fills every promote/retain student of that class
  in the draft, **except** students corrected individually in the draft.
- The row expands to its students, each with its own dropdown filtered by the
  same rule; graduates show "Lulus — tanpa kelas tujuan".
- A source homeroom with `source_ordinal` null shows a warning and no
  dropdowns (the backend would reject any target).

**Draft.** Local state holds `decision_id → homeroom_id | null`. Badge
"N perubahan belum disimpan", buttons Simpan / Batalkan. Save sends only the
changed decisions in one `PATCH .../targets`. On `400`, each
`decision <id>: …` message is shown on that student's row and the draft is
kept; on success the run detail and decisions are refetched and the draft
cleared. With unsaved changes, Eksekusi is disabled and leaving the page
asks for confirmation.

**Placement report** (server data, not the draft): one card per target
homeroom — capacity, existing active, assigned, total, and a yellow
"Melebihi kapasitas" badge when over (warning only). A counter shows
`unassigned`.

### 5.4 Execute dialog

- Summary: counts, target year, over-capacity homerooms.
- `unassigned > 0` → button disabled with "Lengkapi tujuan N siswa dulu".
- Otherwise the user types the target year's name exactly to enable
  Eksekusi.
- A `400` is shown grouped, with Indonesian headings — `target_academic_year`
  "Tahun tujuan", `targets` "Tujuan belum lengkap", `enrollments` "Bentrok
  enrollment", `target_homerooms` "Kelas tujuan tidak valid lagi" — and
  student ids in messages replaced by names from the decisions.
- `409` → alert and refetch (executed elsewhere).
- Success → toast with promoted / retained / graduated; the page becomes
  read-only.

---

## 6. Errors

- User-facing copy for `PROMOTION_RUN_EXISTS`, `PROMOTION_RUN_INVALID_STATUS`,
  `PROMOTION_SELF_APPROVAL` goes into `src/lib/errors/messages.ts`
  (`FORBIDDEN`, `FEATURE_NOT_AVAILABLE`, `VALIDATION_ERROR` exist already).
  Components use `getErrorMessage`, never raw backend messages for codes.
- Field-level `VALIDATION_ERROR` messages from the backend are English; forms
  show them via `applyServerFieldErrors` as today. The grouped execute errors
  and the per-row placement errors show the backend message with the student
  id replaced by the name.
- Unknown or foreign run (`404`) → "Evaluasi tidak ditemukan" page.

---

## 7. Testing

### 7.1 Backend

§3.0.1 and §3.3, per the test cadence in `apps/backend/CONVENTIONS.md` §7.1 (targeted
`--exact` tests per task, full suites once at the final gate).

### 7.2 Web (Vitest, `apps/web/CONVENTIONS.md` §8)

- Zod schemas: criteria, override, target year — one valid and one invalid
  case each at least.
- Pure placement module (the riskiest logic, tested hardest):
  - homeroom filtering by ordinal (promote +1, retain same, null ordinals);
  - applying a class default without overwriting individual corrections;
  - draft diff → PATCH body (only changed decisions; `null` clears);
  - mapping `decision <id>: …` messages to rows.
- Components:
  - decisions table and override dialog (parent spec requires these);
  - action bar shows the right buttons per status × permission;
  - execute dialog: disabled with unassigned students, enabled only after the
    exact year name is typed.

### 7.3 No e2e

The e2e suite needs the whole backend stack and this flow is long. End-to-end
correctness of execution is covered by the backend integration tests from
Plan 3c.

---

## 8. Deliberately out of scope

Printing and its data (Plan 3e), undo, automatic placement, attendance
criterion, Excel export, e2e coverage.
