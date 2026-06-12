# AcademiQ Component Diagram - Identity and Access Service

```mermaid
flowchart TB

subgraph API_Layer
    CTRL[Auth and User REST Controllers]
end

subgraph Application_Layer
    UC1[Public Signup Use Case]
    UC2[Login Use Case - email or username]
    UC3[Assign Role to User Use Case]
    UC4[Manage Permissions Use Case]
    UC5[Manage Tenant Membership Use Case]
    UC6[Tenant Selection Use Case - my-tenants / enter]
    UC7[Google OAuth Login Use Case]
end

subgraph Domain_Layer
    USER[User Entity]
    ROLE[Role Entity]
    PERM[Permission Entity]
    MEMBER[User Tenant Membership Entity]
    AUTH[Authentication Policy]
end

subgraph Infrastructure_Layer
    REPO[Repositories]
    DB[(IAM Database)]
    TOKEN[Token Provider - RS256 JWT, identity + tenant-scoped]
    HASH[Password Hashing Service - Argon2id]
    GOOGLE[Google OIDC Client - code exchange + ID token verify]
end

CTRL --> UC1
CTRL --> UC2
CTRL --> UC3
CTRL --> UC4
CTRL --> UC5
CTRL --> UC6
CTRL --> UC7

UC1 --> USER
UC2 --> AUTH
UC3 --> ROLE
UC4 --> PERM
UC5 --> MEMBER
UC6 --> MEMBER
UC7 --> AUTH

UC1 --> REPO
UC2 --> REPO
UC3 --> REPO
UC4 --> REPO
UC5 --> REPO
UC6 --> REPO
UC7 --> REPO

REPO --> DB
UC2 --> TOKEN
UC6 --> TOKEN
UC7 --> TOKEN
UC7 --> GOOGLE
UC1 --> HASH
UC2 --> HASH
```

## Identity & token notes

- **Login** (`UC2`) accepts an email **or** username identifier and issues a
  tenant-less **identity token**.
- **Tenant selection** (`UC6`) exchanges an identity token for a **tenant-scoped**
  token via `GET /my-tenants` + `POST /tenants/{id}/enter`, checking membership.
- **Google OAuth** (`UC7`) verifies a Google ID token and match-or-creates an
  account, then issues an identity token — IAM remains the sole token issuer (no
  external IdP).
- **Public signup** (`UC1`) creates accounts independent of any tenant; passwords
  are optional (Google-only accounts have none).
