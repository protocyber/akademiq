
# Internal Architecture Documentation Guide

This folder contains the complete internal architecture documentation for the AcademiQ SaaS platform.  
The structure is organized in progressive levels — from business understanding to production engineering standards.

---

## Level 1 — Business (`01_business`)
Describes the high-level business processes of the platform:
- How schools use the system
- Core operational flows (academic year, grading, attendance, billing)
- SaaS business model overview

This level answers: **“What does the business do?”**

---

## Level 2 — Use Cases (`02_use_cases`)
Details user interactions with the system:
- Actors (Admin, Teacher, Student, Parent, Superadmin)
- Functional goals (enroll student, submit grades, upgrade plan)

This level answers: **“What can users do in the system?”**

---

## Level 3 — Domain Model (`03_domain_model`)
Defines core business entities and relationships:
- Student, Teacher, Academic Year, Enrollment, Subscription, etc.

This level answers: **“What are the key concepts in the system?”**

---

## Level 4 — Bounded Context (`04_bounded_context`)
Breaks the domain into logical service boundaries:
- IAM
- Billing
- Academic Config
- Academic Operations
- Attendance
- Grading
- Promotion
- Notification

This level answers: **“How is the business domain divided into services?”**

---

## Level 5 — System Context (`05_system_context`)
Shows how AcademiQ interacts with external systems:
- Payment gateways
- Messaging providers
- Users and administrators

This level answers: **“How does the platform fit into the outside world?”**

---

## Level 6 — Container Architecture (`06_container_archtecture`)
Describes runtime containers:
- Frontend
- API Gateway
- Microservices
- Databases per service

This level answers: **“What deployable applications make up the system?”**

---

## Level 7 — Components (`07_components`)
Details internal structure of each service:
- Controllers
- Use cases
- Domain logic
- Repositories

This level answers: **“How is each service internally structured?”**

---

## Level 8 — Sequences (`08_sequences`)
Sequence diagrams for cross-service workflows:
- Login flow
- Enrollment flow
- Attendance via QR
- Subscription upgrade and renewal

This level answers: **“How do services collaborate during complex operations?”**

---

## Level 9 — States (`09_states`)
State diagrams for lifecycle management:
- Academic Year
- Enrollment
- Student Academic Status (Alumni)
- Report Card
- Class / Homeroom

This level answers: **“How do important entities change over time?”**

---

## Level 10 — Data Design (`10_data_design`)
Database design per service (ERDs):
- Academic Operations
- Grading
- Attendance
- Billing
- IAM
- Academic Config
- Promotion

This level answers: **“How is data structured at rest?”**

---

## Level 11 — Integration Contracts (`11_integration_contracts`)
Defines how services communicate:
- Event contracts (async messaging)
- API schemas (sync REST)

This level answers: **“How does data move between services?”**

---

## Level 12 — Deployment (`12_deployment`)
Infrastructure and runtime reliability:
- Cloud deployment architecture
- Observability (logging, monitoring, tracing)
- Security architecture
- Disaster recovery and high availability

This level answers: **“How does the system run safely and reliably in production?”**

---

## Level 13 — Engineering Standards (`13_engineering_standards`)
Implementation rules for developers:
- Rust tech stack standards
- Repo structure
- API conventions
- CQRS pattern
- Event standards
- CI/CD
- Security baseline
- Validation contract
- Feature entitlement rules

This level answers: **“How should engineers build the system consistently?”**

---

## Summary

These 13 levels together provide a full blueprint of the AcademiQ platform:

**Business → Domain → Services → Data → Integration → Infrastructure → Engineering Standards**

This documentation ensures the platform can be built, scaled, and maintained in a consistent and professional manner.

## Important Naming Convention for the Tenant & Subscription Service 

### Controversy Around Naming the Tenant & Subscription Service vs Billing Service

## Final Naming Strategy (Clean & Practical)

### Architectural Name (docs, diagrams)
**Tenant & Subscription Service**

This stays in:
- Bounded context diagram
- Business docs
- Architecture docs

Because it explains the responsibility clearly.

### Implementation Name (code, DB, logs, infra)
We shorten it to:

**Billing Service**

Yes — billing becomes the technical service name, while the scope still includes subscription + tenant.

This is common in real systems.

### Why “Billing” Is Acceptable Technically
Because in SaaS platforms:

“Billing” often implies subscription + plan + invoice + entitlement

Stripe, Chargebee, etc. all bundle those under “Billing”.

So:

| Concern | Owned by Billing Service? |
| --- | --- |
| Tenant record | ✅ |
| Subscription lifecycle | ✅ |
| Plans | ✅ |
| Feature entitlements | ✅ |
| Invoices/payments | ✅ |

The domain scope stays wide, the name stays short.

### Final Standard (Use This Everywhere in Code)
| Layer | Name to Use |
| --- | --- |
| Service folder | /billing-service |
| Database | billing_db |
| Rust crate | billing_service |
| API base path | /api/v1/billing |
| Event producer | billing_service |
| Docker container | billing-service |

### But In Documentation
Always write:

**Tenant & Subscription (Billing) Service**

First mention can be:

**Tenant & Subscription Service (implemented as Billing Service)**

After that, you can just say Billing Service.

### This Gives You Both
| Context | Name |
| --- | --- |
| Business clarity | Tenant & Subscription |
| Developer ergonomics | Billing |

Best of both worlds.
