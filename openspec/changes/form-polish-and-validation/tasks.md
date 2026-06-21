# Tasks: form-polish-and-validation

Web submodule `apps/web` (items 1–3, 5), backend submodule `apps/backend`
(item 4).

## 1. Default theme → light

- [x] 1.1 In `app/layout.tsx`: change `defaultTheme="system"` to
      `defaultTheme="light"`. Keep `enableSystem`.
- [ ] 1.2 Verify: new incognito window → light theme. Existing user with
      dark preference → stays dark.

## 2. Password toggle on register

- [x] 2.1 In `register/register-client.tsx`: add `const [showPassword,
      setShowPassword] = React.useState(false)`.
- [x] 2.2 Change the password `<Input>` to
      `type={showPassword ? "text" : "password"}`.
- [x] 2.3 Add the eye/eye-off toggle button (copy from `login/page.tsx`).
- [x] 2.4 Import `Eye`, `EyeOff` from lucide-react.

## 3. Subject group code empty-string fix (backend)

- [x] 3.1 In `academic-config-service/src/commands.rs`
      `create_subject_group`: normalize
      `let code = input.code.and_then(|c| { let t = c.trim(); if t.is_empty() { None } else { Some(t.to_string()) } });`
      before `validate_code`.
- [x] 3.2 Same normalization in `update_subject_group`.
- [ ] 3.3 Test: create subject group with `code: ""` → succeeds, stored as
      NULL. Create with `code: "A"` → succeeds, stored as "A".

## 4. Required field markers — convention + sweep

- [x] 4.1 Create a `FormLabelRequired` component (or wrapper) in
      `components/ui/` that renders `<FormLabel>{children} <span
      className="text-destructive">*</span></FormLabel>`.
- [x] 4.2 Document the convention in `apps/web/CONVENTIONS.md`.
- [x] 4.3 Sweep all forms and replace `<FormLabel>` with
      `<FormLabelRequired>` for required fields. Forms to audit (at minimum):
      - `login/page.tsx`
      - `register/register-client.tsx`
      - `set-password/page.tsx`
      - `students-screen.tsx` (StudentDialog)
      - `teachers-screen.tsx` (TeacherDialog)
      - `subjects/page.tsx` (SubjectGroupDialog, SubjectDialog)
      - `years/page.tsx` (IdentitySection)
      - `term-form-modal.tsx` (TermInfoSection)
      - `class-templates/page.tsx` (ClassTemplateDialog)
      - `school-profile/page.tsx` (SchoolProfileForm)
      - `settings/users/page.tsx` (CreateUserDialog, EditUserDialog,
        InviteDialog)
      - `settings/roles/page.tsx`
      - family profile forms (if any)
- [x] 4.4 For each form, cross-reference the Zod schema to determine which
      fields are required (non-optional, min(1)).
- [x] 4.5 Verify: each required field shows red `*`; optional fields don't.

## 5. Verification

- [x] 5.1 `make test` (backend + web) green; lint + typecheck pass.
- [x] 5.2 Manual pass: register with password toggle, submit subject group
      with empty code (succeeds), check required asterisks across forms.
