## MODIFIED Requirements

### Requirement: Accepting an invitation SHALL NOT require choosing a password up front

A user accepting a tenant invitation MUST be able to do so without choosing a
password at accept time. The invited user MAY set a password later via the
self-service set-password flow. Roles and membership are granted on acceptance
regardless of whether a password has been set.

#### Scenario: Invitee joins with a single action

- **WHEN** an invited user accepts the invitation
- **THEN** they gain their tenant membership and a session without being required
  to enter a password during acceptance

#### Scenario: Password set later

- **WHEN** the invited user later completes the set-password flow
- **THEN** password login becomes available for their account
