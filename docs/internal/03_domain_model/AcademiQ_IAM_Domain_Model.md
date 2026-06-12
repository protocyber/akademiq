# AcademiQ Identity & Access Domain Model

## IAM = Identity and Access Management

```mermaid
classDiagram

class User {
  +user_id
  username
  email
  email_verified
  password_hash
  google_sub
  status
  created_at
}

class Role {
  +role_id
  name
  description
}

class Permission {
  +permission_id
  code
  description
}

class UserTenantMembership {
  +membership_id
  user_id
  tenant_id
  role_id
  status
}

class Tenant {
  +tenant_id
  name
}

class TeacherProfile {
  +teacher_id
  user_id
  tenant_id
}

class StudentProfile {
  +student_id
  user_id
  tenant_id
}

class ParentProfile {
  +parent_id
  user_id
  tenant_id
}

class AdminProfile {
  +admin_id
  user_id
  tenant_id
  admin_type
}

User "1" --> "many" UserTenantMembership
Tenant "1" --> "many" UserTenantMembership
Role "1" --> "many" UserTenantMembership

Role "many" --> "many" Permission

User "1" --> "0..1" TeacherProfile
User "1" --> "0..1" StudentProfile
User "1" --> "0..1" ParentProfile
User "1" --> "0..1" AdminProfile
```

## Identity model notes

- **`username`** is the universal identity: `NOT NULL`, globally unique
  (case-insensitive), auto-generated as a slug when not supplied, may not contain
  `@`. Every user has one.
- **`email`** is optional contact + login: nullable, unique when present
  (case-insensitive). Users without an email (e.g. older teachers/parents) log in
  by `username` + password. No synthetic placeholder emails are stored.
- **`password_hash`** is nullable: Google-only accounts have no password.
- **`google_sub`** is the linked Google subject id, unique when present, set when
  an account authenticates via "Login with Gmail". Returning Google users resolve
  by this value before email matching.
- **`email_verified`** flips true on email verification or a verified Google login.
  IAM only auto-links Google to an existing account when Google reports
  `email_verified=true`; unverified Google email collisions do not claim the
  existing account.
- **Identity ≠ membership**: a `User` can exist with **zero**
  `UserTenantMembership` rows (public signup / Google auto-provision) and may
  belong to **many** tenants. Login resolves a user independently of any tenant;
  tenant context is selected afterwards (see the login sequence diagram).
