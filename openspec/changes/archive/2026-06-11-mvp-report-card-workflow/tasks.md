## 1. Roadmap & schema prep

- [x] 1.1 Add/complete the Report Card Workflow phase in `16_implementation_phases.md` (delivering change `mvp-report-card-workflow`, depends on Grade Capture); mark report cards shipped on archive
- [x] 1.2 `V2__report_card.sql` in `grading-service`: `report_card` + `report_approval` per `10_data_design/06_Grading_Service_ERD.md`
- [x] 1.3 Unique `(tenant_id, student_id, academic_year_id)` on `report_card`
- [x] 1.4 Indexes: `report_card(homeroom_id, academic_year_id, status)`, `report_card(student_id, academic_year_id)`, `report_approval(report_card_id)`

## 2. Domain — state machine

- [x] 2.1 `ReportCardStatus` enum (Draft, HomeroomReview, PrincipalApproval, Published, Archived)
- [x] 2.2 Pure transition function `(status, action, role, class-scope) -> Result<status>` covering the full role→transition matrix
- [x] 2.3 Unit tests over the entire (state × action × role) cross-product: every legal transition passes, every illegal one is rejected
- [x] 2.4 Pass/fail derivation from grades + `grading_policy.minimum_passing_score`
- [x] 2.5 Class-scope resolver: does this user act as homeroom teacher / subject teacher of the card's class (via projections + account↔profile link)

## 3. Draft generation

- [x] 3.1 `GenerateReportCards` command: for each enrolled student, aggregate grades, apply policy, upsert `report_card` in Draft with summary jsonb
- [x] 3.2 Idempotent per `(student, year)`: refresh while Draft; skip + report when past Draft
- [x] 3.3 Read grading policy via config (API or projection); read roster + grades via grade-capture queries
- [x] 3.4 Incomplete grades → Draft generated with an `incomplete` flag in summary (not blocked)

## 4. Edit-lock (closes grade-capture seam)

- [x] 4.1 Implement `can_edit_grade(student, year)`: editable only when no report card or card in Draft
- [x] 4.2 Grade write/update returns 409 `GRADES_LOCKED` once card left Draft
- [x] 4.3 `return` transition re-opens editing; integration test for the lock/unlock cycle

## 5. HTTP layer (`/api/v1/grading`)

- [x] 5.1 `POST /report-cards/generate`
- [x] 5.2 `PATCH /report-cards/{id}/submit` (teacher/homeroom)
- [x] 5.3 `PATCH /report-cards/{id}/homeroom-approve` (homeroom)
- [x] 5.4 `PATCH /report-cards/{id}/return` (homeroom)
- [x] 5.5 `PATCH /report-cards/{id}/principal-approve` (principal) → emit `report_card.approved`
- [x] 5.6 `PATCH /report-cards/{id}/reject` (principal)
- [x] 5.7 `GET /report-cards?homeroom_id=&academic_year_id=` (staff board)
- [x] 5.8 `GET /report-cards/{id}` (grades + approval history)
- [x] 5.9 `GET /students/{id}/report-card?academic_year_id=` (published only; 404 to student/parent pre-publish)
- [x] 5.10 Every transition appends a `report_approval` audit row
- [x] 5.11 Wire entitlement middleware (`grading`) on write routes

## 6. Year-close archival

- [x] 6.1 Consume academic-year `Closed`/`Archived` signal; transition that year's `Published` cards → `Archived`
- [x] 6.2 Archived cards are read-only; further transitions rejected

## 7. Integration tests

- [x] 7.1 Generate drafts for a class; one card per enrolled student in Draft
- [x] 7.2 Full happy path: submit → homeroom-approve → principal-approve → Published; `report_card.approved` emitted
- [x] 7.3 Reject/return loops: principal reject → HomeroomReview; homeroom return → Draft (grades editable again)
- [x] 7.4 Wrong role for a transition → 403; illegal transition → 409
- [x] 7.5 Grades locked once card leaves Draft (409 `GRADES_LOCKED`)
- [x] 7.6 Student/parent see card only when Published; pre-publish → 404
- [x] 7.7 Year close archives Published cards; archived are read-only

## 8. Web — workflow + parent view

- [x] 8.1 Zod schemas: generate, transition (with optional note)
- [x] 8.2 TanStack hooks: report-card board, detail, transitions, published view
- [x] 8.3 `/grading/report-cards` — staff board by status with role-appropriate action buttons (spinner); skeleton while loading
- [x] 8.4 `/grading/report-cards/{id}` — grades, pass/fail, approval history, current action
- [x] 8.5 Parent/student portal: published report card read-only view
- [x] 8.6 Generate-drafts action for homeroom teacher / admin

## 9. Cross-service e2e & wrap-up

- [x] 9.1 e2e full rapor chain: register → year+subjects+policy → students+homeroom+enroll+assign → invite teacher+homeroom+principal → record grades → generate drafts → submit → homeroom-approve → principal-approve → published → parent reads it
- [x] 9.2 e2e reject/return loop and grade edit-lock
- [x] 9.3 Playwright: staff workflow board + parent published view
- [x] 9.4 Verify `report_card.approved` matches `events/report-card-approved.md`
- [x] 9.5 Expand `apis/grading-service-api.md` with report-card endpoints
- [x] 9.6 Update `01_repo_structure.md`; mark report-card phase shipped in the roadmap
- [x] 9.7 `openspec validate mvp-report-card-workflow --strict` green
