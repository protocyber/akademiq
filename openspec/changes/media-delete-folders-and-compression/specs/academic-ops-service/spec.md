## ADDED Requirements

### Requirement: Media SHALL support bulk hard deletion per owner

academic-ops-service SHALL expose
`DELETE /api/v1/academic-ops/media?owner_type=&owner_id=` that removes
**all** media asset rows (active and inactive history) for the given owner
within the tenant, deletes every matching storage object (key reconstructed
as `{owner_type}/{media_id}`), and nulls the owning entity's
`photo_media_id`. The operation is tenant-scoped (resolved from the JWT,
never client-supplied) and hard: rows and bytes are permanently removed.

#### Scenario: Bulk delete removes active and history for an owner

- **WHEN** an owner's media is bulk-deleted
- **THEN** all of that owner's `media_asset` rows are removed, every
  matching storage object is deleted, and `photo_media_id` is set to NULL
  on the owning entity

#### Scenario: Bulk delete of an owner with no media succeeds

- **WHEN** bulk delete targets an owner with no media assets
- **THEN** the operation completes without error and no storage object is
  touched

### Requirement: Photo upload SHALL garbage-collect the previous active photo

When a new photo is uploaded for an owner that already has an active photo,
the service SHALL delete the previous active object from storage within the
same transaction that activates the new one. This applies to student,
teacher, and family owner types.

#### Scenario: Replacing a student photo removes the old object

- **WHEN** a student with an existing active photo uploads a new one
- **THEN** the previous photo object is deleted and the new object becomes
  active
