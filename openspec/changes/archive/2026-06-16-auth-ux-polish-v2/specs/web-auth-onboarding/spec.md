## ADDED Requirements

### Requirement: Login submit SHALL remain loading until navigation completes

On a successful login, the submit button MUST stay `disabled` and in its loading
state from submission through the post-login navigation (to the dashboard or
tenant-select), not only while the `login`/`myTenants`/`enterTenant` mutations are
pending. This closes the window where the mutations have resolved but the route
transition is still in progress, during which the re-enabled button would
otherwise accept a second submission. On the failure path the loading state MUST
clear so the button is enabled for retry.

#### Scenario: Button stays loading through navigation

- **WHEN** login succeeds and the app calls `router.push` to the next route
- **THEN** the submit button remains `disabled` and shows the loading spinner until the navigation completes

#### Scenario: Single-tenant fast path keeps loading

- **WHEN** a user with exactly one tenant logs in and the app auto-enters that tenant and pushes to the dashboard
- **THEN** the button stays loading continuously from submit through the dashboard navigation, with no enabled gap

#### Scenario: Failure restores the button

- **WHEN** login (or tenant resolution) fails
- **THEN** the loading state clears and the submit button is enabled for retry
