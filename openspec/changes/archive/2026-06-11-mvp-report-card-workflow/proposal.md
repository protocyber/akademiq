## Why

This is the change that delivers the product target: **a tenant user can
create a report card (rapor)**. The previous three changes built everything a
report card needs — an academic year + subjects + grading policy
(`mvp-academic-config`), enrolled students + teaching assignments
(`mvp-academic-ops`), captured grades (`mvp-grading-grade-capture`), and the
approval actors (`mvp-tenant-user-management`). This change builds the
**report-card half of the `grading-service`**: generating a draft from a
student's grades and driving it through the approval state machine to
publication.

```
Academic Config → Academic Ops → Grading: grade capture → Report Card workflow
   (done)            (done)            (done)                 (this change)
```

The lifecycle is the one in
`docs/internal/09_states/AkademiQ_State_Report_Card_Lifecycle.md`:

```
Draft ─teacher submits grades─▶ HomeroomReview ─homeroom approves─▶ PrincipalApproval
  ▲                                  │                                    │
  └────── needs correction ─────────┘          ┌── rejected ─────────────┘
                                               ▼
PrincipalApproval ─principal approves─▶ Published ─year closed─▶ Archived
```

## What Changes

### Backend — `grading-service` extension (report card workflow)

- New tables per `docs/internal/10_data_design/06_Grading_Service_ERD.md`:
  `report_card` (`report_card_id`, `tenant_id`, `student_id`,
  `academic_year_id`, `homeroom_id`, `status`, `published_at`, plus summary
  fields) and `report_approval` (`approval_id`, `report_card_id`,
  `approver_id`, `role`, `action`, `note`, `approved_at`).
- **Generate draft**: `POST /report-cards/generate` for a homeroom + year
  aggregates each enrolled student's grades (via the grade-capture query),
  applies the year's `grading_policy` (pass/fail vs `minimum_passing_score`),
  and creates one `report_card` per student in `Draft`. Idempotent per
  `(student, year)`.
- **State machine** with role-gated transitions:
  - `PATCH /report-cards/{id}/submit` (subject/homeroom teacher) Draft →
    HomeroomReview.
  - `PATCH /report-cards/{id}/homeroom-approve` (homeroom teacher)
    HomeroomReview → PrincipalApproval.
  - `PATCH /report-cards/{id}/return` (homeroom teacher) HomeroomReview →
    Draft (needs correction).
  - `PATCH /report-cards/{id}/principal-approve` (principal)
    PrincipalApproval → Published; emits `report_card.approved`.
  - `PATCH /report-cards/{id}/reject` (principal) PrincipalApproval →
    HomeroomReview.
  - Year-close consumer: `academic_year` Closed → report cards Published →
    Archived (read-only).
  - Every transition writes a `report_approval` audit row.
- **Edit-lock**: once a report card leaves `Draft`, its grades are locked. This
  fills the `can_edit_grade(student, year)` checkpoint stubbed in the previous
  change so grade edits are rejected once review begins.
- **Role gates** enforce that only the right role performs each transition;
  wrong role → 403, illegal transition → 409 `INVALID_STATE_TRANSITION`.
- **Visibility**: `Published` report cards are readable by the student and
  their parent (`GET /students/{id}/report-card?academic_year_id=`); pre-publish
  cards are visible only to staff in the workflow.
- HTTP additions under `/api/v1/grading`:
  `POST /report-cards/generate`, the transition PATCHes above,
  `GET /report-cards?homeroom_id=&academic_year_id=` (staff board),
  `GET /report-cards/{id}` (with grades + approval history),
  `GET /students/{id}/report-card?academic_year_id=` (published view).
- **Event**: `report_card.approved` (existing contract
  `events/report-card-approved.md`), consumed later by Notification + Promotion.

### Web — report card workflow

- `/grading/report-cards`: staff board listing a class's report cards by status
  with the action available to the current role (submit / homeroom-approve /
  return / principal-approve / reject), each action a spinner-bound control.
- `/grading/report-cards/{id}`: detail showing aggregated grades, pass/fail,
  approval history, and the current-state action.
- Parent/student portal: published report card view (read-only), reachable from
  the existing parent portal page.
- shadcn/ui + TanStack Query + RHF/Zod + two-tier loading.

### Tests & docs

- Unit (state machine: every legal + illegal transition, role gates, pass/fail
  derivation, edit-lock), integration (testcontainer), e2e: the full rapor
  chain end to end — generate draft → teacher submits → homeroom approves →
  principal approves → published → parent sees it; plus a reject/return loop.
  Playwright on the workflow board and the parent view. `report_card.approved`
  contract verified. Roadmap report-card phase marked complete.

## Capabilities

### New Capabilities

- `report-card-workflow`: defines report-card draft generation from grades +
  grading policy, the Draft → HomeroomReview → PrincipalApproval → Published →
  Archived state machine with role-gated transitions and audit trail, the
  grade edit-lock after Draft, published-card visibility to student/parent, and
  the `report_card.approved` event.

### Modified Capabilities

- `grading-service-grade-capture`: the `can_edit_grade` checkpoint becomes a
  real predicate (grades lock once the report card leaves Draft).
- `implementation-roadmap`: the report-card phase is marked shipped.

## Impact

- **New code**: `report_card` + `report_approval` tables and handlers in
  `grading-service`; web workflow board + detail + parent view. **Depends on**:
  `mvp-grading-grade-capture` (grades + per-student query + edit checkpoint),
  `mvp-academic-config` (grading policy), `mvp-academic-ops` (roster),
  `mvp-tenant-user-management` (homeroom teacher + principal accounts).
- **Out of scope**: PDF rendering / file storage (needs the file service —
  deferred; the published card is viewable in-app), notification delivery
  (the event is emitted; delivery waits for the notification service),
  promotion (consumes `report_card.approved` in its own phase).
