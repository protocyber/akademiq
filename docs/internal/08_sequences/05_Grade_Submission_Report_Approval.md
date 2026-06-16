# Sequence Diagram — Grade Submission to Report Approval
```mermaid
sequenceDiagram
participant Teacher
participant WebApp
participant APIGW
participant GRD as Grading Service
participant NOTIF
participant Principal

Teacher->>WebApp: Submit final grades
WebApp->>APIGW: Grade submission
APIGW->>GRD: Store grades
GRD->>GRD: Generate report draft
GRD-->>Principal: Notify report ready
Principal->>GRD: Approve report
GRD-->>NOTIF: Emit ReportCardApproved event
NOTIF-->>Teacher: Report published

# Sequence Diagram — Published Report Card Portal Access (IDOR Protected)

The parent/student read-only portal secures access using projection-based ownership check.

```mermaid
sequenceDiagram
participant Parent as Parent/Student
participant WebApp
participant APIGW
participant GRD as Grading Service

Parent->>WebApp: Open /portal/report-card
WebApp->>APIGW: GET /api/v1/grading/me/report-cards
APIGW->>GRD: Get report cards for auth.user_id
GRD->>GRD: Query student_authz projection for user_id
GRD->>GRD: Filter to only Published/Archived cards
GRD-->>WebApp: Return list of authorized report cards
WebApp->>Parent: Display child selector ("Pilih Anak")
Parent->>WebApp: Select child (or request deep link)
WebApp->>APIGW: GET /api/v1/grading/me/report-cards/:student_id
APIGW->>GRD: Get report card detail
GRD->>GRD: Verify (user_id, student_id) in student_authz
alt Authorized & Published
    GRD-->>WebApp: Return report card details & grades
    WebApp->>Parent: Display report card details
else Unauthorized
    GRD-->>WebApp: Return 403 Forbidden
    WebApp->>Parent: Show Access Denied ("Akses Ditolak")
else Draft (Pre-published)
    GRD-->>WebApp: Return 404 Not Found
    WebApp->>Parent: Show Report Not Available
end
```

```