## ADDED Requirements

### Requirement: School logo SHALL support bulk hard deletion

billing-service SHALL expose
`DELETE /api/v1/billing/media?owner_type=school&owner_id=` that removes
**all** media asset rows (active and inactive history) for the school logo
owner within the tenant, deletes the matching storage objects (key
reconstructed as `school/{media_id}`), and nulls the tenant's
`logo_media_id`. The operation is tenant-scoped (resolved from the JWT,
never client-supplied) and hard.

#### Scenario: Bulk delete removes the school logo history

- **WHEN** the school logo is bulk-deleted
- **THEN** all logo `media_asset` rows are removed, the storage objects are
  deleted, and `logo_media_id` is set to NULL

### Requirement: Logo upload SHALL garbage-collect the previous active logo

The billing-service SHALL garbage-collect the previous active logo when a new logo is uploaded and a previous active logo exists, by deleting the previous logo object from storage within the same transaction that activates the new one.

#### Scenario: Replacing the logo removes the old object

- **WHEN** a tenant uploads a new logo over an existing one
- **THEN** the previous logo object is deleted and the new object becomes
  active
