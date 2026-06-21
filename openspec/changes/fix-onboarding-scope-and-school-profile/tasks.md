# Tasks: fix-onboarding-scope-and-school-profile

Web submodule `apps/web`. No backend changes.

## 1. Academic scope — localStorage read-back

- [x] 1.1 In `academic-scope-provider.tsx`, after `tenantId` and
      `yearsQuery.data` are available, read
      `localStorage[akademiq.academic_scope.<tenantId>]`.
- [x] 1.2 Parse JSON `{ yearId, curriculumId, termId }`; wrap in try/catch
      (on error, fall back to resolver defaults and overwrite stale entry).
- [x] 1.3 Validate `yearId` against `yearsQuery.data`; validate `termId`
      against `termsQuery.data` for the selected year; validate
      `curriculumId` against `curriculumQuery.data`.
- [x] 1.4 If valid, set the scope from persisted values (skip the default
      resolver chain). If any field is stale/invalid, fall back to resolver
      default for that field only.
- [x] 1.5 Test: select Year B → reload → Year B restored. Delete Year B
      → reload → falls back to default.

## 2. Scope-affecting mutation invalidation audit

- [x] 2.1 Audit `useCreateAcademicYear`, `useTransitionAcademicYear`,
      `useDeleteAcademicYear`, `useCreateAcademicTerm`,
      `useTransitionAcademicTerm`, `useDeleteAcademicTerm`,
      `useAddCurriculumVersion`, `useUpdateCurriculumVersion`,
      `useDeleteCurriculumVersion`.
- [x] 2.2 Verify each invalidates: `ACADEMIC_YEARS_QUERY_KEY`,
      `[ACADEMIC_TERMS_QUERY_KEY, yearId]`,
      `[CURRICULUM_VERSIONS_QUERY_KEY, yearId]` as appropriate.
- [x] 2.3 Fill any gaps. (Coordinate with Cluster B task 6 if both are
      in-flight — avoid duplicate invalidation logic.)
- [x] 2.4 Manual test: new tenant → create year → activate → scope
      selectors populate without reload. Create term → scope updates. Create
      curriculum version → scope updates.

## 3. School profile — view mode + edit modal

- [x] 3.1 In `settings/school-profile/page.tsx`, extract a `SchoolProfileView`
      component that renders the profile data as read-only label/value pairs
      grouped by Identitas, Kontak, Alamat. Use the same visual grouping as
      the form. Show "Belum diisi" for empty optional fields.
- [x] 3.2 Add an "Edit" button in the Card header (alongside the title).
- [x] 3.3 Wrap the existing `SchoolProfileForm` in a `Dialog` that opens on
      "Edit" click. The form remains unchanged.
- [x] 3.4 On successful submit: close the dialog, invalidate
      `SCHOOL_PROFILE_QUERY_KEY`, show success toast. The view-mode refetches
      and shows the updated data.
- [x] 3.5 Add a "Batal" button in the dialog footer that closes without
      saving.
- [x] 3.6 Logo upload: keep as-is (it's a separate section, not part of the
      form). Evaluate whether it also moves into the dialog or stays outside.
      Lean: keep the logo upload outside the dialog (it has its own
      upload + history UI).

## 4. Verification

- [x] 4.1 `make test` (web) green; lint + typecheck pass.
- [x] 4.2 End-to-end: new tenant → dashboard empty state → create year →
      activate → scope populates → reload → selection persists → navigate to
      school profile → view mode → edit via modal → save → view refreshes.
