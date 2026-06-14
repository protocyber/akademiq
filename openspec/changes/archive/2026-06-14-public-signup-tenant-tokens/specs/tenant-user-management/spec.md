## MODIFIED Requirements

### Requirement: Invitations SHALL grant membership to an account that may already exist

Accepting a tenant invitation MUST attach a `user_tenant_role` membership to an
account rather than being the sole means of account creation. When the invited
email already matches an existing account, acceptance MUST add the membership to
that account. When no account matches, IAM MUST create the account and the
membership in the same transaction. Account existence is no longer coupled to
invitations — an account may exist with zero memberships (via public signup) and
later gain memberships through invitations.

#### Scenario: Invitation accepted by an existing account

- **WHEN** a user who already has an account (e.g. via public signup) accepts an
  invitation sent to their email
- **THEN** IAM adds a `user_tenant_role` row linking that existing account to the
  inviting tenant, without creating a duplicate account

#### Scenario: Invitation accepted by a new user

- **WHEN** an invitation is accepted for an email that matches no existing account
- **THEN** IAM creates the account and the tenant membership in one transaction,
  as before

#### Scenario: Email-less user invited by an admin

- **WHEN** a tenant admin creates an account for a user without an email and
  assigns a tenant role
- **THEN** the account is created with a generated username and a
  `user_tenant_role` membership, and the user can log in by username + password
