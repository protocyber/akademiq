## Context

### Academic scope provider

`AcademicScopeProvider` (`academic-scope-provider.tsx`) manages the global
"active" year/term/curriculum selection via React Context. It resolves
defaults using `scope-resolvers.ts`:

```
resolveDefaultAcademicYear(years)  → Active year, or latest by start_date
resolveDefaultTerm(terms)          → Active term, or today-overlapping, or latest
resolveDefaultCurriculum(curriculums) → last item in array
```

The resolution chain on mount:
```
isAuthenticated → tenantMe → yearsQuery → set yearId
                                        → curriculumQuery → set curriculumId
                                        → termsQuery → set termId → isResolving=false
```

**The localStorage bug** (lines 52, 92–102):
```ts
const storageKey = tenantId ? `akademiq.academic_scope.${tenantId}` : null;
// ...
useEffect(() => {
  if (!storageKey) return;
  localStorage.setItem(storageKey, JSON.stringify({ yearId, curriculumId, termId }));
}, [storageKey, yearId, curriculumId, termId]);
```

The provider **writes** on every change but never calls
`localStorage.getItem(storageKey)` on mount. Confirmed by grep: `getItem`
does not appear in the file. The `storage` event listener (lines 105–127)
only fires for **cross-tab** changes, not same-tab reloads. So:

```
Tab 1: user selects Year B → localStorage written
Tab 1: user refreshes → localStorage IGNORED → re-resolves to default (Year A)
```

This is the "UI kehilangan konteks" symptom — the selection doesn't survive
a reload.

### Onboarding data gap

A brand-new tenant has zero academic years. The resolution correctly returns
`null`, and the dashboard shows `EmptyStateNoYear`. This is **acceptable** as
a starting point — the user is nudged to create a year. The problem emerges
**after** the user creates and activates a year:

1. User creates year → `ACADEMIC_YEARS_QUERY_KEY` invalidated → scope
   re-resolves → yearId set. (This works IF the create mutation invalidates
   correctly.)
2. User activates year → transition mutation invalidates years query → scope
   should update.
3. User creates curriculum version → scope should pick it up.
4. User creates term → scope should pick it up.

If any of these invalidation chains are incomplete, the scope stays stale and
the user sees empty selectors until they reload. This is the scenario the
user reported ("saat tenant baru onboarding, tahun ajaran baru dibuat, dan
diaktifkan" → scope tetap kosong).

### School profile

`/settings/school-profile/page.tsx` renders a `Card > SchoolProfileForm` —
always editable, no view mode. The form has 13 fields across 3 groups
(Identitas, Kontak, Alamat) plus a logo section. The mutation
`useUpdateSchoolProfile` → `PATCH /billing/tenants/me/school-profile` already
exists and works.

The product request:
```
Current:                          Target:
┌─ Card ──────────────┐          ┌─ Card ──────────────────────┐
│ "Profil Sekolah"    │          │ "Profil Sekolah"  [Edit]    │
│                     │          │                             │
│ [Form: always       │   ──▶    │ ┌─ View mode ─────────────┐ │
│  editable]          │          │ │ Nama: SMA Demo           │ │
│                     │          │ │ NPSN: 123456             │ │
│ [Simpan Perubahan]  │          │ │ ...                      │ │
└─────────────────────┘          │ └──────────────────────────┘ │
                                  └─────────────────────────────┘
                                                │ [Edit click]
                                                ▼
                                  ┌─ Dialog ────────────────────┐
                                  │ "Edit Profil Sekolah"       │
                                  │ [Form: editable]            │
                                  │ [Batal] [Simpan]            │
                                  └─────────────────────────────┘
```

## Goals / Non-Goals

**Goals:**
- The academic scope selection survives page reloads (localStorage read-back).
- After creating/activating a year (and subsequently term/curriculum) during
  onboarding, the scope selectors populate without requiring a manual reload.
- School profile defaults to a read-only view; editing happens in a modal.

**Non-Goals:**
- Adding an onboarding wizard that auto-creates an academic year (the
  `EmptyStateNoYear` nudge is sufficient for now).
- Changing the scope resolution algorithm (Active-first, latest-fallback).
- Changing the school profile fields or backend API.
- Changing the logo upload flow.

## Decisions

### Decision 1: Restore persisted scope with stale-validation

On mount (after `tenantId` is known and before the resolver chain fires),
read `localStorage[akademiq.academic_scope.<tenantId>]`. Parse the JSON and
**validate** each id against the fetched data:

- `yearId`: must exist in `yearsQuery.data` and belong to this tenant.
- `termId`: must exist in `termsQuery.data` for the selected year.
- `curriculumId`: must exist in `curriculumQuery.data` for the selected year.

If any id is stale (the entity no longer exists), fall back to the resolver
default for that field. This prevents restoring a selection that points at a
deleted year/term/curriculum.

```ts
// Pseudo:
const persisted = readAndValidate(storageKey, yearsQuery.data, termsQuery.data, curriculumQuery.data);
if (persisted) {
  setYearId(persisted.yearId ?? resolveDefaultAcademicYear(years));
  // ... only if persisted.yearId is valid
} else {
  // fall back to existing resolver chain
}
```

*Alternative rejected:* blindly restore without validation. Rejected — if a
year was deleted, the scope would point at a ghost id.

### Decision 2: Ensure invalidation covers scope-affecting mutations

Audit all mutations that affect the academic scope's underlying queries:
- `useCreateAcademicYear`, `useTransitionAcademicYear`, `useDeleteAcademicYear`
- `useCreateAcademicTerm`, `useTransitionAcademicTerm`, `useDeleteAcademicTerm`
- `useAddCurriculumVersion`, `useUpdateCurriculumVersion`,
  `useDeleteCurriculumVersion`

Each must invalidate the query keys the scope provider depends on
(`ACADEMIC_YEARS_QUERY_KEY`, `[ACADEMIC_TERMS_QUERY_KEY, yearId]`,
`[CURRICULUM_VERSIONS_QUERY_KEY, yearId]`). Most already do; verify and fill
gaps. This overlaps with Cluster B's invalidation broadening — coordinate so
both are done in one pass if possible.

### Decision 3: School profile — view mode as read-only field grid

Render the profile data as a read-only grid (label + value pairs) using the
same visual structure as the form groups (Identitas, Kontak, Alamat). Use
`<dl>` or a simple grid of `<div>` pairs. An "Edit" button in the CardHeader
opens a `Dialog` containing the existing `SchoolProfileForm` (reused as-is).
On successful submit, the dialog closes and the view-mode query refetches.

*Alternative rejected:* use a `Sheet` (slide-over) instead of a `Dialog`.
Rejected — the form is long (13 fields); a centered Dialog with max-height +
scroll is more appropriate than a side sheet.

## Risks / Trade-offs

- **[Risk] Stale localStorage after schema change** → if the stored shape
  changes, parsing fails. *Mitigation:* wrap in try/catch; on parse error,
  fall back to resolver defaults and overwrite the stale entry.
- **[Risk] Scope restores a selection the user didn't expect after a long
  absence** → acceptable; the resolver default is only used when the
  persisted value is invalid.
- **[Risk] View-mode layout doesn't match form layout** → *Mitigation:* use
  the same group structure so the visual transition from view to edit is
  seamless.

## Migration Plan

1. **Scope provider:** add localStorage read-back + validation. Deploy.
2. **Invalidation audit:** verify all scope-affecting mutations invalidate
   correctly (coordinate with Cluster B). Deploy.
3. **School profile:** extract view-mode rendering; add edit dialog. Deploy.
4. **Verify:** create a new tenant → create year → activate → scope
   selectors populate → reload page → selection persists → edit school
   profile via modal.

## Open Questions

- Should the scope also persist to the backend (user preference) rather than
  just localStorage? Lean: no for now — localStorage is sufficient; backend
  persistence is a future enhancement.
- Should the school profile view-mode show empty-state hints for unset
  fields (e.g. "Belum diisi")? Lean: yes, to distinguish "no data" from
  "loading".
