# Sequence Diagram — Academic Year Initialization

The "copy previous year setup" flow is **orchestrated by the web app** (the
copy wizard). Services never call each other: the browser calls one copy
endpoint per service, in order, and carries the source→target `id_map` from
academic-config to academic-ops and grading. Progress is recorded on an
`academic_year_copy_run` row in academic-config so an interrupted copy can be
resumed ("Lanjutkan"). Each service step is one DB transaction and is
idempotent (existing target data is skipped, never overwritten). Design:
`docs/superpowers/specs/2026-11-12-academic-year-copy-design.md`.

```mermaid
sequenceDiagram
participant Admin
participant Web as WebApp (copy wizard)
participant ACFG as Academic Config Service
participant AOPS as Academic Ops Service
participant GRD as Grading Service

Admin->>Web: Create Draft year / open "Salin dari tahun lain"
Web->>ACFG: GET /academic-years/{target}/copy-runs/current
alt in-progress run exists
  ACFG-->>Web: run (items, id_map, *_result)
  Web-->>Admin: "Lanjutkan" banner, resume at first part without result
else no run
  ACFG-->>Web: 404
  Admin->>Web: Pick source year, items, term dates
  Web->>ACFG: POST /academic-years/copy (dry_run=true)
  ACFG-->>Web: would-be counts
  Web->>AOPS: POST /academic-years/copy (dry_run=true)
  Web->>GRD: POST /academic-years/copy (dry_run=true)
  Admin->>Web: Confirm
  Web->>ACFG: POST /academic-years/{target}/copy-runs
  ACFG-->>Web: 201 copy_run_id (409 COPY_RUN_IN_PROGRESS if one exists)
end

Web->>ACFG: POST /academic-years/copy (copy_run_id, items, term_dates)
Note over ACFG: one tx: terms, grade levels, class templates,<br/>curriculum, subjects, grading policy.<br/>Stores config_result + id_map on the run.
ACFG-->>Web: results + id_map

Web->>AOPS: POST /academic-years/copy (copy_run_id, id_map)
alt projection not ready
  AOPS-->>Web: 409 COPY_DEPENDENCY_NOT_READY
  Web->>AOPS: retry after short delay
end
AOPS-->>Web: results (classes, homeroom teachers, assignments, timetable)
Web->>ACFG: PATCH /copy-runs/{id} {step: "ops", result}

Web->>GRD: POST /academic-years/copy (copy_run_id, id_map)
alt projection not ready
  GRD-->>Web: 409 COPY_DEPENDENCY_NOT_READY
  Web->>GRD: retry after short delay
end
GRD-->>Web: results (report types, evaluation weights)
Web->>ACFG: PATCH /copy-runs/{id} {step: "grading", result}

Web->>ACFG: PATCH /copy-runs/{id} {status: "completed"}
Web-->>Admin: Summary (copied / skipped per item)

opt Admin cancels
  Web->>ACFG: PATCH /copy-runs/{id} {status: "cancelled"}
  Note over ACFG: Nothing is rolled back
end
```

Resume: the wizard reads the run, skips parts whose `*_result` is already
stored, and re-sends the stored `id_map` for the remaining parts. Re-running a
finished part is safe — everything reports as skipped.
