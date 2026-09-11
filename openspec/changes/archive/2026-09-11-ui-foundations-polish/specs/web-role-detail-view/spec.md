## ADDED Requirements

### Requirement: Admins SHALL view a role's permissions in a read-only dialog

The roles screen MUST provide a View action, enabled for every role including
built-in roles, that opens a read-only dialog listing the role's active
permissions. The dialog MUST NOT expose edit controls and MUST work for built-in
roles whose Edit action is disabled, so admins can inspect the permissions of
default roles they cannot modify.

#### Scenario: View a built-in role's permissions

- **WHEN** an admin clicks View on a built-in role whose Edit action is disabled
- **THEN** a read-only dialog opens listing that role's active permissions with
  no edit controls

#### Scenario: View action is available for custom roles too

- **WHEN** an admin clicks View on a custom role
- **THEN** the same read-only dialog opens showing its active permissions
