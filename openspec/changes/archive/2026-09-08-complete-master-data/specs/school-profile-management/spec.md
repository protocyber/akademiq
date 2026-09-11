## ADDED Requirements

### Requirement: Admin sekolah can manage complete school profile
The system SHALL allow an authorized admin sekolah to view and update the current tenant's school profile with identity, contact, address, and branding fields.

The profile SHALL include school name, address, phone number, email, website, optional NPSN, logo reference, school level, public/private status, accreditation, village/subdistrict/city-or-regency/province, and postal code. The profile SHALL NOT include kepala sekolah/head-teacher linkage in this change.

#### Scenario: Admin updates school profile
- **WHEN** an authorized admin sekolah submits valid school profile data for the current tenant
- **THEN** the system stores the profile under the tenant resolved from the JWT and returns the updated profile

#### Scenario: Tenant isolation is enforced
- **WHEN** an admin sekolah requests or updates the school profile
- **THEN** the system only reads or writes the profile for the tenant resolved from the JWT and ignores any client-supplied tenant identifier

#### Scenario: Head teacher is not part of school profile
- **WHEN** school profile data is viewed or updated
- **THEN** the profile does not require or expose a head teacher identifier

### Requirement: User-facing tenant wording becomes sekolah
The web UI SHALL use sekolah terminology for user-facing tenant concepts while preserving backend/API/code `tenant` terminology.

#### Scenario: Admin views tenant-owned pages
- **WHEN** an admin sekolah views tenant-owned pages, settings, navigation, labels, empty states, and validation messages
- **THEN** user-facing copy refers to sekolah rather than tenant
