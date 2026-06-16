## Context

Every page that needs an academic year keeps its own selection today: `grading/entry` uses a
local `yearId` state + `QuerySelect`; `report-cards` has its own year `QuerySelect`;
`teaching-assignments` keeps `academic_year_id` in the URL params. Curriculum, where it
appears, is hard-picked (`grading/entry` takes `curriculum.data?.[0]`). There is no shared
notion of "the current year". The header (`sidebar-layout.tsx`) shows only the institution
name and theme/avatar controls.

Curriculum versions are fetched per year (`useCurriculumVersions(yearId)`), so year and
curriculum are not independent.

The project has one `React.createContext` in use today (form context) and a `theme-provider`
wrapping the app; there is precedent for a small context provider. TanStack Query is the
data-access layer (`CONVENTIONS.md`).

## Goals / Non-Goals

**Goals:**
- One global academic scope (year + curriculum) in the header, persisted in `localStorage`,
  exposed via Context, consumed by every page that needs it.
- Default to the Active year + newest curriculum; empty + prompt when no Active year exists.
- Remove all per-page year/curriculum selectors.

**Non-Goals:**
- Sharing the scope across tenants or persisting server-side — scope is a per-browser UI
  preference.
- Removing URL params used for shareability beyond year scope (e.g. report_type_id stays in
  the URL).
- Changing the header layout other than adding the selectors.

## Decisions

### D1: `localStorage` + React Context (per the user's choice)
Store `{ academic_year_id, curriculum_version_id }` in `localStorage` under a tenant-scoped
key (so switching tenants does not reuse another tenant's year). A `AcademicScopeProvider`
reads it on mount, exposes `{ yearId, curriculumId, setYear, setCurriculum }`, and writes
through to `localStorage` on change.

_Alternative_: URL search param as the source of truth. Rejected by the user (they chose
localStorage). A URL param has merits (shareable, per-tab) but the user wants persistence
without requiring it in the URL; the chosen approach still lets pages read the value
deterministically.

### D2: Resolve defaults client-side after queries load
`useAcademicYears` returns the list; on first load the provider selects `status === "Active"`
(first match, or newest by `start_date` if preferred). When a year is chosen, the provider
queries `useCurriculumVersions(yearId)` and selects the newest version. If no Active year
exists, the scope stays empty and the UI shows a prompt.

_Alternative_: a dedicated "current scope" backend resource. Rejected — over-engineered for a
UI preference; the client already has the data via existing queries.

### D3: Tenant-scoped localStorage key
Key includes the `tenant_id` (from `useTenantMe`) so a year from tenant A is never applied to
tenant B. If the tenant is unknown yet, the provider waits (skeleton) rather than guessing.

### D4: Hydration caution
Next.js SSR cannot read `localStorage`. The provider MUST read `localStorage` inside a
`useEffect` (client-only) and render a neutral default until then, to avoid hydration
mismatches. Pages that depend on the scope treat "loading" as a skeleton.

## Risks / Trade-offs

- **Hydration mismatch** → Mitigated by D4 (client-only read; no server render of the value).
- **Stale year id in localStorage after a year is deleted** → The provider validates the
  stored id against the fetched year list and resets to the Active default if it is gone.
- **Per-tab divergence lost** → `localStorage` is shared across tabs of the same browser;
  changing the year in one tab updates others via the `storage` event (listen for it in the
  provider). This is acceptable for a UI scope.
- **Regression: a page keeps a hidden local picker** → Mitigated by an explicit sweep in the
  tasks (grep for `QuerySelect`/year usage) and a test asserting no page-level year picker
  remains on the converted screens.

## Migration Plan

1. Add `AcademicScopeProvider` (Context + localStorage + tenant-scoped key) and the header
   selector components.
2. Wire `useAcademicScope()` into grade entry, report board, teaching assignments, homerooms.
3. Sweep for and remove remaining page-level year/curriculum pickers.
4. Add tests for default resolution, empty state, persistence, and the "no page picker"
   invariant.
5. Rollback: additive (the provider and selectors are new); removing them restores local
   pickers. The only non-additive step is deleting page pickers — do that last.

## Open Questions

- Key the `localStorage` entry per tenant, or globally? (Design says per tenant — D3.)
- Should the curriculum selector be hidden on pages that do not use curriculum (e.g. report
  board), or always shown in the header for consistency? (Lean: always shown, it is a global
  scope.)
