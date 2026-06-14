## ADDED Requirements

### Requirement: Web SHALL offer public self-service signup

The web app MUST provide a signup page that submits email + password (and an
optional username) to `POST /auth/register` and, on success, treats the returned
identity token as an authenticated session pending tenant selection.

#### Scenario: Visitor signs up

- **WHEN** a visitor completes the signup form with a valid email and password
- **THEN** the client calls `POST /auth/register`, stores the identity token, and
  proceeds to tenant selection (which shows the 0-tenant empty state for a brand
  new account)

### Requirement: Web SHALL resolve tenant context after login

After any successful login or signup, the client MUST call `GET /my-tenants` and
branch: zero memberships → 0-tenant empty state; exactly one → automatically call
`POST /tenants/{id}/enter` and proceed into the app (single-tenant fast path);
many → present a tenant picker, entering the chosen tenant via
`POST /tenants/{id}/enter`. A "switch school" action MUST re-invoke `/enter` for a
different tenant.

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

### Requirement: Auth guards SHALL treat identity-only sessions as valid but limited

Routing guards MUST recognize "authenticated with an identity token, no tenant
entered" as a valid state that may reach only tenant-less routes (profile,
tenant list, invitation acceptance). Tenant-scoped pages MUST require a
tenant-scoped token and redirect an identity-only session to tenant selection.

#### Scenario: Identity-only session is kept out of tenant pages

- **WHEN** a user holding only an identity token navigates to a tenant-scoped page
- **THEN** the guard redirects them to tenant selection rather than rendering the
  page or logging them out
