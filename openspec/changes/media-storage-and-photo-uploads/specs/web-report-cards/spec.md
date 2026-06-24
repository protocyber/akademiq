## ADDED Requirements

### Requirement: The report-card print page SHALL render the student photo

The report-card print page SHALL display the student's photo when the student
has an active `photo_media_id`, resolved through the academic-ops media serve
endpoint. To preserve print fidelity, the photo SHALL be rendered with a plain
image element using a resolved absolute media URL (not the image optimizer).
When the student has no photo, the page MUST render without error.

#### Scenario: Student with a photo

- **WHEN** the print page renders for a student who has an active photo
- **THEN** the student's photo is displayed from the resolved media URL

#### Scenario: Student without a photo

- **WHEN** the print page renders for a student with no photo
- **THEN** the page renders without an image and without error
