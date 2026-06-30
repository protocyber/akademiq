## ADDED Requirements

### Requirement: Avatar upload SHALL garbage-collect the previous object

When an IAM user uploads a new avatar, the service SHALL delete the previous
avatar object (at `avatar/{previous_media_id}`) from storage before the new
avatar becomes active. IAM uses a single `avatar_url` column (no
`media_asset` table), so the previous object is identified by parsing the
existing `avatar_url`. If no previous avatar exists, no deletion is
performed.

#### Scenario: Replacing an avatar removes the old object

- **WHEN** a user with an existing avatar uploads a new one
- **THEN** the previous avatar object is deleted from storage and the new
  object is stored at `avatar/{new_media_id}`

#### Scenario: First avatar upload deletes nothing

- **WHEN** a user with no avatar uploads one
- **THEN** no previous-object deletion occurs

### Requirement: Avatar deletion SHALL remove stored bytes

The `DELETE /api/v1/iam/me/avatar` endpoint SHALL delete the stored avatar
object at `avatar/{media_id}` and set `avatar_url` to NULL. This resolves
the prior behavior that only nulled the column and orphaned the bytes.
Deletion is idempotent.

#### Scenario: Deleting an avatar removes bytes and clears the column

- **WHEN** a user deletes their avatar
- **THEN** the avatar object is removed from storage and `avatar_url` is
  set to NULL
