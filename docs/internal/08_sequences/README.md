# AcademiQ Level 8 Sequence Diagrams

These diagrams describe critical cross-service runtime flows in AcademiQ.
<!-- 
1. User Login with Tenant Resolution — Authentication and multi-tenant role resolution.
2. Academic Year Initialization — Creating a new academic year based on prior configuration.
3. Student Enrollment — Assigning students to classes with rule validation.
4. QR Attendance Scan — Real-time attendance via QR code.
5. Grade Submission to Report Approval — Teacher grading through principal approval.
6. End of Year Promotion — Determining student promotion or retention.
7. Plan Upgrade with Proration — Mid-cycle subscription upgrade handling.
8. Subscription Renewal — Automatic or manual renewal process. -->

These flows involve multiple services and are key to system reliability and maintainability.

Sequence diagrams can explode in number if we don’t choose them strategically.

At Level 8, we only create sequence diagrams for flows that cross multiple services or contain critical business logic.

Not every feature deserves one.

## 🎯 Criteria for Creating a Sequence Diagram

We create one when a flow:

- ✅ Involves 3+ services
- ✅ Has state changes
- ✅ Has money, approval, or academic impact
- ✅ Has async/event-driven behavior
- ✅ Would be painful to debug later without a visual flow

## 🧩 Recommended Sequence Diagrams for AcademiQ

Here is the professional shortlist for your platform.

### 🟢 1️⃣ User Login (Multi-Tenant Resolution)

Why important: Foundation of security & tenant isolation

Services involved:
- Web App
- API Gateway
- IAM Service
- Tenant Service (resolve memberships)

Flow includes:
- Credential validation (email or username; or Login with Gmail)
- Identity-token issuance, then tenant selection (`/my-tenants` → `/enter`)
- Tenant-scoped token issuance after membership check

### 🟢 2️⃣ Academic Year Initialization Flow

Why important: Core yearly configuration logic

Services involved:
- Academic Config Service
- Academic Ops Service
- Possibly Grading Service

Flow includes:
- Clone previous year setup
- Create new year snapshot
- Initialize structures

### 🟢 3️⃣ Student Enrollment Flow

Why important: Impacts attendance, grading, reporting

Services involved:
- Academic Ops Service
- Academic Config Service
- Notification Service

Flow includes:
- Assign student to class
- Validate against year config
- Emit event

### 🟢 4️⃣ QR Attendance Scan Flow

Why important: High-frequency operational flow

Services involved:
- Attendance Service
- Academic Ops Service
- IAM (student identity)
- Notification Service (optional absence alert)

Flow includes:
- QR validation
- Session check
- Record attendance
- Emit event

### 🟢 5️⃣ Teacher Submits Grades → Report Card Approval

Why important: Multi-step academic workflow

Services involved:
- Grading Service
- Academic Ops Service
- Notification Service

Flow includes:
- Grade submission
- Report generation
- Homeroom review
- Principal approval
- Parent notification

### 🟢 6️⃣ End-of-Year Promotion Process

Why important: Yearly academic lifecycle

Services involved:
- Grading Service
- Promotion Service
- Academic Ops Service
- Notification Service

Flow includes:
- Evaluate grades
- Decide promoted/retained
- Move student records
- Notify stakeholders

### 🟢 7️⃣ Plan Upgrade with Proration ✅ (Already Done)

Why important: Billing-heavy cross-service flow.

Services involved:
- Tenant Admin
- WebApp
- API Gateway
- Tenant & Subscription Service
- Payment Gateway
- Feature Access Service

Flow includes:
- Request plan upgrade
- Upgrade request
- Calculate proration & upgrade cost
- Price difference
- Charge prorated amount
- Payment success
- Record subscription change & activate new plan
- Update feature entitlements
- Upgrade successful

### 🟢 8️⃣ Subscription Renewal ✅ (Already Done)

Why important: Lifecycle & billing continuity.

Services involved:
- System Scheduler
- Tenant & Subscription Service
- Payment Gateway
- Feature Access Service
- Tenant Admin

Flow includes:
- Check subscriptions near expiry
- Send renewal reminder
- Confirm renewal
- Charge renewal amount
- Payment success
- Extend subscription period
- Ensure feature continuity
- Renewal successful

## 🧠 Summary Table

| # | Sequence Diagram | Domain Area |
| --- | --- | --- |
| 1 | User Login (Multi-Tenant) | IAM |
| 2 | Academic Year Initialization | Academic Config |
| 3 | Student Enrollment | Academic Ops |
| 4 | QR Attendance Scan | Attendance |
| 5 | Grade Submission → Report Approval | Grading |
| 6 | End-of-Year Promotion | Promotion |
| 7 | Plan Upgrade | Billing |
| 8 | Subscription Renewal | Billing |

That’s a complete and professional Level 8 set. Not too many, not missing critical ones.
