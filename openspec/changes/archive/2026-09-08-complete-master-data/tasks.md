## 1. Contracts and data model planning

- [x] 1.1 Update docs/internal ERDs for Billing tenant profile and Academic Ops student, teacher, family profile, student-family link, and media metadata ownership
- [x] 1.2 Update API contracts for Billing school profile endpoints and Academic Ops rich profile/family/media endpoints
- [x] 1.3 Decide and document whether media upload uses a new File service path or a minimal service-local adapter for this change
- [x] 1.4 Define canonical enum values for school level, school status, accreditation, profile statuses, archive reasons, relationships, and media owner types

## 2. Billing school profile backend

- [x] 2.1 Add Billing migration for tenant school profile identity, address, contact, and branding fields without head-teacher linkage
- [x] 2.2 Add Billing domain/repository support for reading and updating the current tenant school profile
- [x] 2.3 Add Billing HTTP handlers, validation, and tenant-scoped routes for school profile read/update
- [x] 2.4 Add Billing tests for tenant isolation, validation, update success, and absence of head-teacher linkage

## 3. Academic Ops profile backend

- [x] 3.1 Add Academic Ops migrations for expanded student profile fields, status, archive reason, soft delete metadata, and media reference
- [x] 3.2 Add Academic Ops migrations for expanded teacher profile fields, status, archive reason, soft delete metadata, and media reference
- [x] 3.3 Update Academic Ops domain, repositories, commands, and HTTP schemas for rich student and teacher profile create/update/list/detail behavior
- [x] 3.4 Implement student create with optional initial enrollment attempt that preserves the student profile when placement fails
- [x] 3.5 Add tests for rich student/teacher profiles, independent IAM contact data, archive reasons, soft delete visibility, and enrollment boundary behavior

## 4. Family profile backend

- [x] 4.1 Add Academic Ops migrations for family_profile and student_family_link with reusable many-to-many relationships and link status
- [x] 4.2 Implement family profile CRUD, archive, soft delete, search, and optional IAM user linkage without IAM synchronization
- [x] 4.3 Implement student-family link create/update/list/inactivate behavior with relationship attributes
- [x] 4.4 Implement duplicate warning detection for matching NIK, phone, or identifying details without blocking creation
- [x] 4.5 Add tests for reusable family profiles, sibling links, multiple family links per student, inactive links, duplicate warnings, and optional IAM linkage

## 5. Guardian access separation

- [x] 5.1 Ensure family profile linking does not create guardian access links automatically
- [x] 5.2 Ensure guardian access links can still be managed independently of family profiles
- [x] 5.3 Add regression tests that family link changes do not mutate guardian access rows or report-card authorization projections

## 6. Media upload and history

- [x] 6.1 Add media asset metadata model for school, teacher, student, and family owners with active asset and history semantics
- [x] 6.2 Implement upload validation for JPG, PNG, and WebP files up to 2MB
- [x] 6.3 Implement replace behavior that makes the new asset active and keeps previous assets visible in history
- [x] 6.4 Add tests for valid uploads, invalid file type/size rejection, tenant/owner scoping, and history visibility

## 7. Web UI

- [x] 7.1 Update user-facing web copy from tenant to sekolah where it describes the current school/tenant concept
- [x] 7.2 Add or update Profil Sekolah page for complete Billing school profile read/update and logo history
- [x] 7.3 Expand teacher forms, tables, detail views, status/archive behavior, and photo history UI
- [x] 7.4 Expand student forms, tables, detail views, status/archive behavior, optional initial placement flow, and photo history UI
- [x] 7.5 Add student detail Keluarga tab with search existing, create new, duplicate warning, link attributes, and inactive link handling
- [x] 7.6 Preserve explicit guardian access management separately from family biodata UI

## 8. Imports, validation, and verification

- [x] 8.1 Update student and teacher import templates and row validation for the expanded field sets
- [x] 8.2 Add or update centralized frontend schemas, API clients, query hooks, and mutation hooks for all new/modified endpoints
- [x] 8.3 Run backend tests for affected services
- [x] 8.4 Run web lint, typecheck, and tests
- [x] 8.5 Run parent orchestrator verification target if practical for the final integrated change
