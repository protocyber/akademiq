## MODIFIED Requirements

### Requirement: Web SHALL resolve tenant context after login

After any successful login or signup, the client MUST call `GET /my-tenants` and
branch: zero memberships → 0-tenant empty state; exactly one → automatically call
`POST /tenants/{id}/enter` and proceed into the app (single-tenant fast path);
many → present a tenant picker, entering the chosen tenant via
`POST /tenants/{id}/enter`. A "switch school" action MUST re-invoke `/enter` for a
different tenant. During the single-tenant fast path, the client MUST keep a
loading state and MUST NOT visibly render the tenant picker before dashboard
navigation completes.

#### Scenario: Single-tenant user lands directly in the app

- **WHEN** a user with exactly one membership logs in
- **THEN** the client auto-enters that tenant and the experience matches a direct
  login-into-app flow, with no visible picker

#### Scenario: Multi-tenant user picks a school

- **WHEN** a user with more than one membership logs in
- **THEN** the client shows a tenant picker and enters the selected tenant on
  choice

#### Scenario: Zero-tenant user sees an empty state

- **WHEN** an authenticated user has no memberships
- **THEN** the client shows a "You're not part of any school yet" screen and
  restricts navigation to tenant-less routes

#### Scenario: Single-tenant auto-enter does not flash picker

- **WHEN** tenant selection resolves exactly one tenant and starts auto-entering it
- **THEN** the page remains in a loading state until dashboard navigation is initiated and no tenant list card is rendered for that single tenant

#### Scenario: Single-tenant login ignores stale tenant-select next target

- **WHEN** a user with exactly one membership logs in from `/login?next=/tenant-select`
- **THEN** the client auto-enters the tenant and navigates to `/dashboard` rather than rendering `/tenant-select`

#### Scenario: Scoped user cannot remain on tenant selection

- **WHEN** a user already has a tenant-scoped access token and reaches `/tenant-select`
- **THEN** the client redirects to `/dashboard` without rendering the tenant picker

### Requirement: The accept-invitation page SHALL be a single confirm action

The accept-invitation page MUST be reachable by unauthenticated public visitors,
including clean incognito sessions with no stored tokens. Global providers and
background queries MUST NOT start tenant-scoped authenticated requests that
redirect the visitor away from the invitation page before the invitation token can
be displayed or accepted. The page MUST present a single primary action ("Terima
Undangan") rather than a form requiring name and password. Accepting calls the
invitation-accept endpoint with the token and navigates the now-signed-in user
into the app. A user whose account has no password yet MUST be guided (banner or
CTA) to a separate set-password screen.

> Web work is sequenced **after** the `iam-service` backend changes in this same
> change land (passwordless accept + set-password endpoint).

#### Scenario: One-click accept

- **WHEN** the user opens a valid invitation link and clicks "Terima Undangan"
- **THEN** the invitation is accepted, a session is established, and the user is
  taken into the app without entering a name or password

#### Scenario: Prompt to set a password

- **WHEN** an accepted user has no password set
- **THEN** the app surfaces a path to the set-password screen

#### Scenario: Incognito visitor can open invitation link

- **WHEN** an unauthenticated visitor with no stored identity, access, or refresh token opens `/invitations/accept?token=<valid-token>`
- **THEN** the invitation acceptance page renders the invitation state and MUST NOT redirect to `/login`

#### Scenario: Global academic scope stays idle on public invitation page

- **WHEN** the invitation acceptance page renders without a tenant-scoped access token
- **THEN** academic scope queries that require tenant authentication are disabled and no authenticated academic-config request is issued
