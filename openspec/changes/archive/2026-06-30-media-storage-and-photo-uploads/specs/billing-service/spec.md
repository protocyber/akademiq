## ADDED Requirements

### Requirement: Billing SHALL serve the school logo and resolve its storage URI

The billing service SHALL expose `GET /api/v1/billing/media/:media_id` that
streams the stored school-logo bytes with their recorded content type. The
school media list endpoint SHALL resolve each asset's storage reference to a
servable HTTP media path (or `media_id`) instead of returning a raw `media://`
URI, so the web app can render the logo.

#### Scenario: School logo is served

- **WHEN** a client requests an existing billing media id
- **THEN** the service responds 200 with the stored content type and the logo bytes

#### Scenario: Media list returns resolvable paths

- **WHEN** the school media list is requested
- **THEN** each asset exposes a resolvable HTTP media path rather than a raw `media://` URI
