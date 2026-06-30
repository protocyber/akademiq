## Why

Four small UI/validation polish issues that improve form usability and
consistency across the app.

**Issue #1 — default theme should be light.** `layout.tsx` sets
`defaultTheme="system"` which causes an unpredictable first-paint (dark on
OS-dark-mode users). The product wants `light` as the default for new
visitors.

**Issue #2 — register form lacks a password visibility toggle.** The login
form (`login/page.tsx:278-286`) has an eye/eye-off toggle on the password
field. The register form (`register/register-client.tsx:209-224`) does not —
it's a plain `type="password"` input. Users want the same UX as login.

**Issue #15 — required fields lack visual markers.** Across all forms, the
`<FormLabel>` does not show a red asterisk (`*`) on required fields. Users
can't tell which fields are mandatory without submitting and seeing
validation errors. The convention should be: if the Zod schema marks a field
as required (non-optional, `min(1)`), the label shows a red `*`.

**Issue #16 — subject group code validation mismatch.** The frontend schema
(`subject.ts:10`) marks `code` as `z.string().optional()` and the UI label
says "Kode (opsional)". But the backend's `validate_code`
(`commands.rs:1097-1102`) rejects empty strings with "must not be empty".
The root cause: the frontend sends `code: ""` (the form's default empty
string) instead of `undefined`/`null`. The backend deserializes `""` as
`Some("")`, then `validate_code` rejects it. So the user sees a validation
error on a field the UI said was optional.

## What Changes

- **Default theme → light.** Change `layout.tsx`
  `defaultTheme="system"` → `defaultTheme="light"`. Keep `enableSystem` so
  users can still switch to system/dark via the theme switcher.
- **Password toggle on register.** Add the same `showPassword` state + eye
  icon toggle to the register form's password field.
- **Required field markers.** Establish a convention: required fields render
  a red `*` in the `<FormLabel>`. This can be done either by:
  - (a) A wrapper component `<RequiredFormLabel>` that appends the asterisk,
    or
  - (b) Updating each form's `<FormLabel>` to include
    `<span className="text-destructive">*</span>` for required fields.
  Audit all forms and apply the marker consistently.
- **Subject group code fix.** The frontend mutation should omit `code` from
  the payload when it's empty (send `undefined`/`null`), OR the backend
  should treat `Some("")` as `None`. The cleaner fix is frontend: transform
  `code: ""` → `undefined` before sending. This avoids sending meaningless
  empty strings.

## Capabilities

### Modified Capabilities
- `web-forms`: default theme is light; password toggle on register; required
  field markers across all forms; subject group code empty-string handling.

## Impact

- **Web** (`apps/web`):
  - `app/layout.tsx`: one-line theme default change.
  - `app/register/register-client.tsx`: add password toggle state + icon.
  - All form files: add required-field asterisks (sweep — many files).
  - `lib/query/mutations/use-academic-config.ts` or
    `app/settings/academic/subjects/page.tsx`: transform `code: ""` →
    `undefined` before sending.
- **No backend changes** (the subject group code fix is frontend-side).
- **No migration.**
