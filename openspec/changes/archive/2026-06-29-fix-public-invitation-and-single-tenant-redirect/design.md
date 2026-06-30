## Context

The web app mounts `AcademicScopeProvider` globally from the root layout. That provider resolves tenant academic context for authenticated app pages, but it currently calls academic-config TanStack Query hooks even when there is no tenant-scoped access token. Because those hooks use authenticated API client requests, public routes such as `/invitations/accept` can be redirected to `/login` before their own public page guard finishes rendering.

The tenant selection page already has a single-tenant fast path, but it sets the tenant list before the auto-enter navigation finishes. This can briefly render the picker even though the requirement says single-tenant users should go directly into the app.

## Goals / Non-Goals

**Goals:**

- Keep invitation acceptance accessible from unauthenticated/incognito sessions.
- Ensure global academic scope resolution is inert until a tenant-scoped access token exists.
- Preserve authenticated tenant-scoped protection for dashboard/settings/grading pages.
- Prevent single-tenant users from seeing the tenant picker during auto-enter.

**Non-Goals:**

- Change invitation backend contracts.
- Change token storage or refresh semantics.
- Redesign login, invitation, or tenant picker visuals.
- Add server-side middleware.

## Decisions

1. Gate academic scope queries at the query-hook level and provider call site.

   The academic year query should accept an `enabled` option, mirroring existing conditional query patterns. `AcademicScopeProvider` should pass `enabled: isAuthenticated` so no authenticated academic-config request is started before an access token exists.

   Alternative considered: remove `AcademicScopeProvider` from the root layout and mount it only under authenticated page shells. That is cleaner architecturally but more invasive because the app currently relies on the provider being globally available.

2. Keep invitation acceptance as a public route.

   The invitation page can continue to use its current page-level public behavior. The bug is not that invitation needs auth; it is that unrelated global tenant queries are redirecting public visitors.

   Alternative considered: special-case `/invitations/accept` inside the API client redirect logic. That would hide the symptom while allowing unauthenticated tenant-scoped requests to continue firing from public pages.

3. Model single-tenant auto-entry as a loading/navigation state, not as a rendered picker state.

   The tenant-select page should avoid storing/rendering the singleton tenant list as a selectable list while `enterTenant` and dashboard navigation are in progress.

   Alternative considered: allow the list to render and rely on fast navigation. That keeps code simpler but preserves the flicker reported by the user.

4. Treat `/tenant-select` as an identity-only routing surface.

   After a tenant has been entered and a scoped access token exists, `/tenant-select` should not remain renderable. If a scoped user reaches it through a stale `next=/tenant-select` value or direct navigation, the app should redirect to `/dashboard`.

   The login single-tenant fast path should also normalize unsafe or stale `next` targets such as `/tenant-select` to `/dashboard` after `enterTenant` succeeds.

## Risks / Trade-offs

- Conditional academic queries may skip expected scope initialization if token detection does not update after tenant entry. Mitigation: base the provider's enabled state on access-token presence and existing token-change events.
- Adding query `enabled` options can affect callers that expect unconditional fetches. Mitigation: default enabled behavior should remain true unless explicitly disabled.
- Tenant-select navigation may stay on skeleton if auto-enter fails and state is not reset. Mitigation: failure paths must clear the auto-enter loading state and show an error/empty selectable state.
