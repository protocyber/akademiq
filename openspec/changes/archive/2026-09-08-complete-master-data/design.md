## Context

Current architecture already assigns tenant/subscription ownership to Billing, identity/access to IAM, academic setup to Academic Config, and operational school rosters to Academic Ops. Student, teacher, enrollment, homeroom, and guardian access are already in Academic Ops, while Billing currently stores only minimal school identity for the tenant.

The requested master data spans several bounded contexts. Treating it as one generic service would cut across existing ownership and add a new deployable/database before the domain has proven that boundary. The safer design is to enrich the existing owners and keep login access, enrollment, school identity, family biodata, and media history distinct.

## Goals / Non-Goals

**Goals:**

- Store complete school identity/contact/address/branding fields under Billing as tenant profile data.
- Expand Academic Ops student and teacher profile data while preserving current enrollment and IAM boundaries.
- Add reusable family profiles in Academic Ops and support many-to-many links to students.
- Keep guardian portal access explicit and separate from family biodata.
- Support logo/photo uploads with visible history and validation rules.
- Replace user-facing `tenant` wording with `sekolah` in the web UI.

**Non-Goals:**

- Create a new generic master-data service.
- Rename backend/API/code identifiers from `tenant` to `school`.
- Move IAM user, role, permission, or credential ownership out of IAM.
- Store current class directly on the student as authoritative state.
- Model kepala sekolah/head teacher in this change.
- Automatically grant portal access from family-profile linkage.

## Decisions

### Keep master data distributed by bounded context

Billing will own school profile data because the tenant represents the subscribing school. Academic Ops will own student, teacher, family, and student-family link data because these are operational school records used by enrollment, rosters, assignments, imports, and downstream academic workflows. IAM remains the owner of login accounts and roles.

Alternative considered: create a `master-data-service`. Rejected for now because current docs already assign the relevant entities to Billing and Academic Ops, and a new service would require new database ownership, API/event contracts, projections, infrastructure routing, and cross-service coordination.

### School profile excludes kepala sekolah for now

The school profile will include identity, contact, address, logo, NPSN, level, school status, and accreditation fields, but will not include `head_teacher_id` or principal assignment. Kepala sekolah can be introduced later when document/signature/report-card requirements need it.

Alternative considered: store `head_teacher_id` in Billing as an opaque Academic Ops UUID plus snapshot name. Rejected because it couples Billing to Academic Ops for a role that is not needed yet.

### Student class placement remains enrollment-owned

Student profile data will not own current class. Initial student creation may optionally attempt placement into a homeroom for an academic year, but failure to enroll must not roll back the student profile. The UI should surface the resulting state as “belum ditempatkan di kelas”.

Alternative considered: add `current_class_id` to student. Rejected because enrollment already stores academic-year-scoped placements and historical class movement.

### Family profiles are biodata, guardian links are access

Family profiles will store administrative biodata and may optionally link to an IAM user. Student-family links will store relationship attributes such as relationship type, primary contact, emergency contact, living-with-student, financial responsibility, and active/inactive state. Existing guardian links remain the explicit portal/report-card authorization relationship.

Alternative considered: treat guardian IAM users as the only family model. Rejected because schools need biodata for ayah/ibu/wali even when those people do not have login accounts.

### Profile and IAM data can differ

Teacher, student, and family profile email/phone fields are administrative contact data. Linked IAM user email and membership data remain login/access data and do not need to synchronize automatically.

Alternative considered: force profile and IAM contact data to match. Rejected because schools often maintain administrative phone/email data that differs from the account used for login.

### Media history is visible

Logo and photo uploads will use file-backed assets with JPG/PNG/WebP validation and a 2MB maximum. Replacing a logo/photo creates a new active asset and keeps prior assets visible in history.

Alternative considered: store only the current file URL. Rejected because the user requested visible history and because auditability is useful for administrative records.

### Media storage uses a service-local adapter now, migratable to File service later

For this change, media upload will be implemented as a **minimal service-local adapter** in each owning service (Billing for school logos, Academic Ops for people photos). The adapter stores binary content in a configurable local volume/object path and records `media_asset` metadata rows in the owning service's database. The `file` feature code remains in the plan matrix for future use.

When a dedicated File service is introduced later, the adapter's storage backend can be swapped (same media metadata schema, different content location) without changing the API contract or the `media_asset` table shape.

Alternative considered: build the dedicated File service now. Rejected because it adds a new deployable, new database ownership, cross-service routing, and projections before the media domain has proven its boundary — and the only consumers in this change are the profile endpoints that already live in Billing and Academic Ops.

## Risks / Trade-offs

- Cross-service school/profile data could require multiple API calls in the UI → keep screens context-specific and avoid backend cross-database reads.
- Family duplicate warnings may allow duplicate profiles → warn on matching NIK/phone/name but allow continuation to preserve admin flexibility.
- Media history increases storage usage → enforce 2MB limit and keep asset metadata separate from profile rows.
- Existing imports may lag richer fields → update templates and validation in the same change.
- User-facing rename from tenant to sekolah may miss strings → include a UI copy audit task.

## Migration Plan

1. Add additive migrations for Billing tenant profile fields/tables and Academic Ops profile/family/media metadata.
2. Backfill existing tenants, students, and teachers with default active statuses and empty optional fields.
3. Preserve existing APIs while extending response/request shapes additively where possible.
4. Add new endpoints for family profile and media history operations.
5. Update frontend screens and forms.
6. Update docs/internal API contracts and ERDs.

Rollback should disable new UI entry points first, then leave additive nullable columns/tables in place until a later cleanup migration.

## Open Questions

- ~~Should media storage be implemented through a dedicated File service now, or as a minimal service-local adapter that can later migrate to File service?~~ **Resolved**: service-local adapter now, migratable later (see Decisions).
- ~~Which exact school levels, accreditation values, and Indonesian administrative area fields should be enumerated versus free text?~~ **Resolved**: enumerated for `school_level`, `school_status`, `accreditation`; free text for administrative area components (village, subdistrict, city/regency, province, postal code) since Indonesia has no compact canonical enum source suitable for this change.
- ~~Should family profile duplicate detection use only exact NIK matches or also fuzzy name/phone matching?~~ **Resolved**: exact match on NIK, exact match on phone, and case-insensitive full-name match — surfaced as a non-blocking warning.
