## ADDED Requirements

### Requirement: The tenant-select zero-tenant state SHALL offer a path to register a new school

The `ZeroTenantState` component in `tenant-select/page.tsx` MUST render a
primary "Daftar Sekolah Baru" button that navigates to
`/register?mode=existing`. The button MUST appear above or alongside the
existing "Keluar" button. The empty-state message remains unchanged
("Anda belum terdaftar di sekolah mana pun. Tunggu undangan dari admin
sekolah untuk bergabung, atau daftar sekolah baru.").

#### Scenario: Tenant-less user sees registration CTA

- **WHEN** an authenticated tenant-less user lands on `/tenant-select`
- **THEN** the zero-tenant state shows a "Daftar Sekolah Baru" button that
  navigates to `/register?mode=existing`

### Requirement: The register page SHALL support an existing-user mode

The register wizard (`register-client.tsx`) MUST support `?mode=existing` in
the URL search params. In this mode the wizard is 2 steps — "Profil sekolah"
and "Pilih plan" — and MUST NOT render the "Akun Admin" step. The submit
calls the `register-for-user` endpoint with `{ school_name, plan_id }` and
the identity token. On success, the client enters the new tenant and
redirects to `/dashboard`.

#### Scenario: Existing-user register wizard

- **WHEN** an authenticated tenant-less user navigates to
  `/register?mode=existing`
- **THEN** the wizard shows 2 steps (school profile, plan); no admin
  credentials are requested; submit creates the tenant and redirects to
  `/dashboard`

#### Scenario: Existing-user mode requires authentication

- **WHEN** an unauthenticated user navigates to `/register?mode=existing`
- **THEN** they are redirected to `/login` (the endpoint requires an identity
  token)
