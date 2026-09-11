## MODIFIED Requirements

### Requirement: The academic scope SHALL restore the user's last selection on mount

`AcademicScopeProvider` MUST read the persisted scope selection from
`localStorage` (key `akademiq.academic_scope.<tenantId>`) on mount, after
the tenant id is known and the academic-years query has resolved. The
provider MUST validate each persisted id (yearId, termId, curriculumId)
against the fetched data; any id that no longer exists MUST fall back to the
resolver default. If parsing fails or the entry is absent, the provider
MUST use the resolver defaults (current behavior).

#### Scenario: Selection persists across page reload

- **WHEN** a user selects Year B, then reloads the page
- **THEN** the scope restores Year B (not the resolver default), because the
  persisted value is still valid

#### Scenario: Stale selection falls back to default

- **WHEN** a user reloads and the persisted `yearId` refers to a year that
  has been deleted
- **THEN** the scope falls back to `resolveDefaultAcademicYear` instead of
  restoring the stale id

### Requirement: School profile SHALL display in view mode with an edit modal

The `/settings/school-profile` page MUST render the profile data in a
read-only view by default, grouped by Identitas, Kontak, and Alamat. A
"Edit" button in the card header MUST open a `Dialog` containing the
editable `SchoolProfileForm`. On successful submit, the dialog closes and
the view-mode data refreshes.

#### Scenario: View mode is the default

- **WHEN** a user navigates to `/settings/school-profile`
- **THEN** the profile fields are displayed as read-only label/value pairs;
  no inline editing is possible without clicking "Edit"

#### Scenario: Edit modal opens and saves

- **WHEN** a user clicks "Edit", modifies fields in the dialog, and clicks
  "Simpan"
- **THEN** the update mutation fires; on success the dialog closes, a
  success toast shows, and the view-mode data refreshes to reflect the
  changes

### Requirement: Scope-affecting mutations SHALL invalidate all dependent queries

Create, transition, and delete mutations for academic years, terms, and
curriculum versions MUST invalidate the query keys that
`AcademicScopeProvider` depends on, so the scope selectors populate without
requiring a manual page reload.

#### Scenario: Scope populates after year creation and activation

- **WHEN** a new tenant user creates an academic year and activates it
- **THEN** the academic scope selectors in the sidebar populate with the new
  year without requiring a page reload
