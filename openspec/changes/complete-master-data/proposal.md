## Why

AkademiQ needs richer school master data so admin sekolah can manage complete operational records for the school, teachers, students, family profiles, and media without overloading IAM or duplicating enrollment history. Current student/teacher data is minimal, guardian access already exists, and UI terminology still exposes technical `tenant` wording instead of user-facing `sekolah`.

## What Changes

- Add complete school profile data under Billing as tenant-owned school identity/contact/branding data, without principal/head-teacher linkage in this change.
- Expand Academic Ops student and teacher profiles with richer Indonesian school administration fields, lifecycle status, archive reasons, and optional IAM account linkage that remains separate from profile data.
- Add reusable family profiles in Academic Ops with many-to-many links to students, link attributes, duplicate warnings, and optional IAM user linkage that does not automatically grant portal access.
- Keep enrollment year-scoped through existing homeroom/enrollment flows; student master data must not store current class as authoritative state.
- Add upload-backed logo/photo support with visible media history for school logos and teacher/student/family photos.
- Update web UI wording so user-facing `tenant` terminology becomes `sekolah` while backend/API/code terminology may remain `tenant`.
- Preserve existing guardian portal access as a separate explicit student-user link flow.

## Capabilities

### New Capabilities
- `school-profile-management`: Admin sekolah can manage complete school identity, address, contact, and branding profile data for the current tenant.
- `family-profile-management`: Admin sekolah can manage reusable family profiles and link them to one or more students with relationship metadata.
- `profile-media-history`: Admin sekolah can upload, replace, remove, and view history for school logos and people photos.

### Modified Capabilities
- `academic-ops-service`: Expand student and teacher profile requirements, lifecycle/archive behavior, create-student placement behavior, and family profile integration while preserving enrollment boundaries.
- `billing-service`: Extend tenant-facing school profile requirements without moving academic people data into Billing.
- `student-guardian-linking`: Clarify that guardian portal access remains explicit and separate from family biodata profiles.

## Impact

- Backend: billing-service tenant profile APIs/data model; academic-ops-service student, teacher, family profile, student-family link, import/export, and media-reference integration.
- Frontend: admin sekolah pages for Profil Sekolah, student detail Keluarga tab, richer teacher/student forms, media upload/history UI, and tenant-to-sekolah wording updates.
- Integrations: IAM remains identity-only with optional `user_id` links; enrollment remains academic-year/homeroom based; future or existing file/media service is required for binary uploads and history.
- Docs/contracts: update internal ERDs, API contracts, OpenSpec specs, and user-facing terminology guidance.
