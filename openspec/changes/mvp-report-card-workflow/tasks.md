## 1. Roadmap & schema prep

- [ ] 1.1 Add/complete the Report Card Workflow phase in `16_implementation_phases.md` (delivering change `mvp-report-card-workflow`, depends on Grade Capture); mark report cards shipped on archive
- [ ] 1.2 `V2__report_card.sql` in `grading-service`: `report_card` + `report_approval` per `10_data_design/06_Grading_Service_ERD.md`
- [ ] 1.3 Unique `(tenant_id, student_id, academic_year_id)` on `report_card`
- [ ] 1.4 Indexes: `report_card(homeroom_id, academic_year_id, status)`, `report_card(student_id, academic_year_id)`, `report_approval(report_card_id)`

## 2. Domain — state machine

- [ ] 2.1 `ReportCardStatus` enum (Draft, HomeroomReview, PrincipalApproval, Published, Archived)
- [ ] 2.2 Pure transition function `(status, action, role, class-scope) -> Result<status>` covering the full role→transition matrix
- [ ] 2.3 Unit tests over the entire (state × action × role) cross-product: every legal transition passes, every illegal one is rejected
- [ ] 2.4 Pass/fail derivation from grades + `grading_policy.minimum_passing_score`
- [ ] 2.5 Class-scope resolver: does this user act as homeroom teacher / subject teacher of the card's class (via projections + account↔profile link)

## 3. Draft generation

- [ ] 3.1 `GenerateReportCards` command: for each enrolled student, aggregate grades, apply policy, upsert `report_card` in Draft with summary jsonb
- [ ] 3.2 Idempotent per `(student, year)`: refresh while Draft; skip + report when past Draft
- [ ] 3.3 Read grading policy via config (API or projection); read roster + grades via grade-capture queries
- [ ] 3.4 Incomplete grades → Draft generated with an `incomplete` flag in summary (not blocked)

## 4. Edit-lock (closes grade-capture seam)

- [ ] 4.1 Implement `can_edit_grade(student, year)`: editable only when no report card or card in Draft
- [ ] 4.2 Grade write/update returns 409 `GRADES_LOCKED` once card left Draft
- [ ] 4.3 `return` transition re-opens editing; integration test for the lock/unlock cycle

## 5. HTTP layer (`/api/v1/grading`)

- [ ] 5.1 `POST /report-cards/generate`
- [ ] 5.2 `PATCH /report-cards/{id}/submit` (teacher/homeroom)
- [ ] 5.3 `PATCH /report-cards/{id}/homeroom-approve` (homeroom)
- [ ] 5.4 `PATCH /report-cards/{id}/return` (homeroom)
- [ ] 5.5 `PATCH /report-cards/{id}/principal-approve` (principal) → emit `report_card.approved`
- [ ] 5.6 `PATCH /report-cards/{id}/reject` (principal)
- [ ] 5.7 `GET /report-cards?homeroom_id=&academic_year_id=` (staff board)
- [ ] 5.8 `GET /report-cards/{id}` (grades + approval history)
- [ ] 5.9 `GET /students/{id}/report-card?academic_year_id=` (published only; 404 to student/parent pre-publish)
- [ ] 5.10 Every transition appends a `report_approval` audit row
- [ ] 5.11 Wire entitlement middleware (`grading`) on write routes

## 6. Year-close archival

- [ ] 6.1 Consume academic-year `Closed`/`Archived` signal; transition that year's `Published` cards → `Archived`
- [ ] 6.2 Archived cards are read-only; further transitions rejected

## 7. Integration tests

- [ ] 7.1 Generate drafts for a class; one card per enrolled student in Draft
- [ ] 7.2 Full happy path: submit → homeroom-approve → principal-approve → Published; `report_card.approved` emitted
- [ ] 7.3 Reject/return loops: principal reject → HomeroomReview; homeroom return → Draft (grades editable again)
- [ ] 7.4 Wrong role for a transition → 403; illegal transition → 409
- [ ] 7.5 Grades locked once card leaves Draft (409 `GRADES_LOCKED`)
- [ ] 7.6 Student/parent see card only when Published; pre-publish → 404
- [ ] 7.7 Year close archives Published cards; archived are read-only

## 8. Web — workflow + parent view

- [ ] 8.1 Zod schemas: generate, transition (with optional note)
- [ ] 8.2 TanStack hooks: report-card board, detail, transitions, published view
- [ ] 8.3 `/grading/report-cards` — staff board by status with role-appropriate action buttons (spinner); skeleton while loading
- [ ] 8.4 `/grading/report-cards/{id}` — grades, pass/fail, approval history, current action
- [ ] 8.5 Parent/student portal: published report card read-only view
- [ ] 8.6 Generate-drafts action for homeroom teacher / admin

## 9. Cross-service e2e & wrap-up

- [ ] 9.1 e2e full rapor chain: register → year+subjects+policy → students+homeroom+enroll+assign → invite teacher+homeroom+principal → record grades → generate drafts → submit → homeroom-approve → principal-approve → published → parent reads it
- [ ] 9.2 e2e reject/return loop and grade edit-lock
- [ ] 9.3 Playwright: staff workflow board + parent published view
- [ ] 9.4 Verify `report_card.approved` matches `events/report-card-approved.md`
- [ ] 9.5 Expand `apis/grading-service-api.md` with report-card endpoints
- [ ] 9.6 Update `01_repo_structure.md`; mark report-card phase shipped in the roadmap
- [ ] 9.7 `openspec validate mvp-report-card-workflow --strict` green
