## ADDED Requirements

### Requirement: School logo SHALL support single media deletion

billing-service SHALL expose a tenant-scoped operation that deletes one school logo media asset by `media_id`. The operation MUST only delete media where `owner_type` is `school` and `owner_id` matches the tenant resolved from the authenticated request. It MUST remove the selected media row and its backing storage object without deleting other school logo history rows.

#### Scenario: Inactive history item is deleted

- **WHEN** an authenticated tenant admin deletes an inactive school logo media asset by `media_id`
- **THEN** billing-service removes only that media asset row and its backing storage object
- **AND** other school logo media assets remain available in the media list
- **AND** the tenant's active `logo_media_id` is unchanged

#### Scenario: Active logo item is deleted

- **WHEN** an authenticated tenant admin deletes the active school logo media asset by `media_id`
- **THEN** billing-service removes that media asset row and its backing storage object
- **AND** billing-service sets the tenant's `logo_media_id` to NULL
- **AND** billing-service does not promote another historical logo to active

#### Scenario: Media outside the tenant school owner is not deleted

- **WHEN** a delete request references a media asset that does not belong to the authenticated tenant's school owner
- **THEN** billing-service does not delete the media asset or storage object
- **AND** the response indicates the asset was not found or not accessible

### Requirement: School profile UI SHALL allow deleting logo history items

The web school profile settings page SHALL render a delete control for each image in the logo history section. Deleting a history item MUST call the single media deletion operation and refresh the school profile and school media data after success.

#### Scenario: Admin deletes a logo history image

- **WHEN** an admin uses the delete control for a logo history image on `/settings/school-profile`
- **THEN** the web app requests deletion for that image's `media_id`
- **AND** the logo history list refreshes without the deleted image after the operation succeeds

#### Scenario: Admin deletes the active logo from history

- **WHEN** an admin deletes the active logo image from the logo history section
- **THEN** the web app refreshes school profile and school media data
- **AND** the page shows no current logo after the operation succeeds
