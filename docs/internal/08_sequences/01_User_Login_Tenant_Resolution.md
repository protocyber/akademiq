# Sequence Diagram — User Login with Tenant Resolution

Login is a **two-step exchange** (identity token → tenant-scoped token). A user
authenticates with an email **or** username (or "Login with Gmail"), receives a
tenant-less **identity token**, then *enters* a tenant to obtain the
tenant-scoped token that the rest of the system already verifies. A user may
belong to zero, one, or many tenants.

```mermaid
sequenceDiagram
participant User
participant WebApp
participant IAM as IAM Service
participant Google as Google OAuth

User->>WebApp: Enter identifier (email or username) + password
WebApp->>IAM: POST /auth/login { identifier, password }
note over IAM: identifier contains '@' → match email<br/>else → match username
IAM-->>WebApp: Identity token (sub, typ=identity, no tenant)

opt Login with Gmail
  User->>WebApp: Click "Login with Gmail"
  WebApp->>IAM: GET /auth/google/start
  note over IAM: store state + PKCE verifier with short TTL
  IAM-->>Google: Redirect (state + PKCE challenge)
  Google-->>IAM: GET /auth/google/callback?code&state
  note over IAM: verify ID token (JWKS, aud, iss, exp)<br/>match google_sub → email(verified) → auto-provision
  IAM-->>WebApp: Redirect /auth/callback?identity_token=...
end

WebApp->>IAM: GET /my-tenants (identity token)
IAM-->>WebApp: [] | [one] | [many]

alt Zero tenants
  WebApp-->>User: "You're not part of any school yet" empty state
else One tenant (fast path)
  WebApp->>IAM: POST /tenants/{id}/enter (identity token)
  IAM-->>WebApp: Tenant-scoped access + refresh token
  WebApp-->>User: Land in the app
else Many tenants
  WebApp-->>User: Tenant picker
  User->>WebApp: Choose tenant
  WebApp->>IAM: POST /tenants/{id}/enter (identity token)
  IAM-->>WebApp: Tenant-scoped access + refresh token
  WebApp-->>User: Land in the app (chosen tenant)
end
```

## Notes

- **Identity token**: `{ sub, typ:"identity" }`, short-lived, non-refreshable. It
  authorizes tenant-less routes. `/me` and `/my-tenants` also accept a
  tenant-scoped access token, so a user who has entered a tenant need not retain
  the identity token.
- **Tenant-scoped token**: `{ sub, tenant_id, roles, perms, typ:"access" }` — the
  token every other service verifies. Only `POST /tenants/{id}/enter` mints it,
  and only after checking `user_tenant_role` membership. Carries `roles[]` (role
  identity) and the deduplicated `perms[]` union (authorization).
- **Refresh tokens are tenant-scoped**: refreshing renews the same tenant's token
  using the refresh token alone (no live access token needed); switching tenants
  is a fresh `/enter`, not a refresh.
- **Identity ≠ membership**: accounts are created by public signup, by Google
  auto-provisioning, or by invitation; tenant membership is granted separately by
  accepting an invitation. An account can exist with no tenants.
- **Google callback errors** redirect to `/auth/callback?oauth_error=...`; the
  web app surfaces the error and returns the user to login.
