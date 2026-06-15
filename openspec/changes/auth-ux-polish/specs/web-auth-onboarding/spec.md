## MODIFIED Requirements

### Requirement: Login submit SHALL remain in a loading state until navigation completes

On a successful login, the submit button MUST stay disabled and in its loading
state from submission through the post-login navigation (to the dashboard or
tenant-select), not only while the login/tenant mutations are pending. This
prevents a second submission during the window where the mutations have resolved
but the route transition is still in progress.

#### Scenario: Button stays loading through navigation

- **WHEN** login succeeds and the app begins navigating to the next route
- **THEN** the submit button remains disabled and shows the loading state until
  the navigation completes

#### Scenario: Failure restores the button

- **WHEN** login fails
- **THEN** the loading state clears and the button is enabled for retry

### Requirement: API client SHALL attach access tokens and refresh on 401

The API client MUST attach the tenant-scoped access token to authenticated
requests and, on a 401 indicating an expired/invalid access token, attempt a
single-flight refresh and retry the original request once before redirecting.

In addition, the client MUST refresh **proactively in the background**: it MUST
schedule a refresh shortly before the access token's `exp` so a continuously
active session is renewed without surfacing an expiry-driven error or redirect.
Proactive and reactive refresh MUST share the same single-flight guard so
concurrent triggers never issue overlapping refreshes. The schedule MUST be
(re)armed when tokens are set/refreshed and cleared on logout.

#### Scenario: Proactive refresh before expiry

- **WHEN** an access token is approaching its `exp` while the user is active
- **THEN** the client refreshes in the background and subsequent requests use the
  new token without any visible error

#### Scenario: Reactive refresh remains a safety net

- **WHEN** a request returns 401 with an expired/invalid access-token code
- **THEN** the client performs a single-flight refresh and retries the request
  once before redirecting

#### Scenario: Single-flight is preserved

- **WHEN** proactive and reactive refresh would trigger at the same time
- **THEN** only one refresh request is in flight and both await its result

#### Scenario: Logout cancels the schedule

- **WHEN** the user logs out
- **THEN** any pending background-refresh timer is cleared
