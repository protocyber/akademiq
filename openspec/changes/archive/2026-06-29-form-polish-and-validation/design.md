## Context

Four independent polish items. Each is small but touches different parts of
the form system.

### Item 1: Default theme

`layout.tsx` line 39:
```tsx
<ThemeProvider attribute="class" defaultTheme="system" enableSystem>
```

The product wants new visitors to see the light theme by default. Changing
`defaultTheme` to `"light"` means:
- First-time visitors get light (regardless of OS preference).
- Returning users who previously picked dark/system keep their choice
  (next-themes persists to localStorage under the `class` attribute).

`enableSystem` stays true so the theme switcher's "Sistem" option still
works.

### Item 2: Password toggle on register

Login (`login/page.tsx:278-286`):
```tsx
const [showPassword, setShowPassword] = React.useState(false);
// ...
<Input type={showPassword ? "text" : "password"} ... />
<Button type="button" onClick={() => setShowPassword(s => !s)}>
  {showPassword ? <EyeOff/> : <Eye/>}
</Button>
```

Register (`register-client.tsx:209-224`):
```tsx
<Input type="password" autoComplete="new-password" {...field} />
// No toggle
```

Fix: copy the same pattern.

### Item 3: Required field markers

Current convention: `<FormLabel>Nama</FormLabel>` — no visual distinction
between required and optional.

Target:
```
Required:  Nama *        (asterisk in text-destructive / red)
Optional:  Kode (opsional)
```

Some forms already label optional fields with "(opsional)" in the text
(e.g. subject group code). The new convention:
- Required fields: label text + red `*`.
- Optional fields: keep the "(opsional)" suffix OR just omit the `*`.

Approach: create a `RequiredFormLabel` or a `FormLabelRequired` wrapper:

```tsx
function FormLabelRequired({ children }: { children: React.ReactNode }) {
  return (
    <FormLabel>
      {children} <span className="text-destructive">*</span>
    </FormLabel>
  );
}
```

Then sweep all forms: for each `<FormField>`, check the Zod schema — if the
field is required, use `<FormLabelRequired>` instead of `<FormLabel>`.

The sweep covers (at minimum):
- login form, register form, set-password form
- student dialog, teacher dialog
- subject group dialog, subject dialog
- academic year form, term form
- class template dialog
- school profile form
- user create/edit dialogs, invitation dialog
- role dialogs
- family profile forms (if any)

### Item 4: Subject group code empty-string bug

The data flow:
```
Form default:     code: ""           (empty string)
Zod schema:       code: z.string().optional()  — "" passes (it's a valid string)
Mutation body:    { name, code: "", position }
Backend deser:    AddSubjectGroupBody.code: Option<String> = Some("")
Backend validate: validate_code("code", "") → REJECT ("must not be empty")
```

Two fix options:

**Option A (frontend)**: Before sending, transform `code` — if empty string,
send `undefined` (omit the key or send `null`):
```ts
const payload = { ...values, code: values.code?.trim() || undefined };
await add.mutateAsync(payload);
```

**Option B (backend)**: In `validate_code`, treat `Some("")` as `None`
(skip validation). Or in the command handler, normalize:
```rust
let code = input.code.and_then(|c| if c.trim().is_empty() { None } else { Some(c) });
```

*Lean: Option B (backend)* — normalizing empty strings to None at the
deserialization boundary is more robust. It catches the issue for ALL
optional string fields, not just `code`. But Option A is simpler and
lower-risk if we want to avoid backend changes. Given this is a polish
cluster, **Option A (frontend)** is preferred for minimal blast radius.

Actually, **Option B is better** because:
1. The same bug likely affects other optional string fields across the API.
2. Normalizing at the boundary means the frontend doesn't need per-field
   transforms.
3. It's a 2-line change in the command handler.

*Final lean: Option B* — normalize `Some("")` → `None` for optional string
fields in the subject group create/update handlers. If the pattern is common,
consider a shared deserialization helper. For now, just fix subject group
since that's the reported bug.

## Goals / Non-Goals

**Goals:**
- New visitors see light theme by default.
- Register form has the same password toggle as login.
- Required fields are visually marked across all forms.
- Subject group code doesn't trigger validation when left empty.

**Non-Goals:**
- Redesigning the form system or creating a form generator.
- Changing the Zod schema for subject group code (it's already optional).
- Changing any backend validation logic beyond the empty-string
  normalization for subject group code.

## Decisions

### Decision 1: `FormLabelRequired` wrapper, not inline asterisks

Create a reusable `<FormLabelRequired>` component rather than adding
`<span className="text-destructive">*</span>` inline in every form. This
ensures consistency and makes future changes (e.g. switching from `*` to a
different marker) a one-file change.

### Decision 2: Backend empty-string normalization for subject group code

In `create_subject_group` and `update_subject_group` command handlers,
normalize: `let code = input.code.and_then(|c| if c.trim().is_empty() { None } else { Some(c.trim().to_string()) });`
before validation. This treats `Some("")` the same as `None`.

### Decision 3: Keep `enableSystem` on the theme provider

Users can still switch to system/dark. Only the *default* for first-time
visitors changes to light.

## Risks / Trade-offs

- **[Risk] Required-field sweep is wide** — many forms to touch.
  *Mitigation:* do it systematically; grep for `<FormLabel>` and check each
  field's schema. Create a checklist.
- **[Risk] Backend empty-string normalization changes behavior for other
  callers** — any API client that sends `code: ""` expecting it to be stored
  as empty string will now get `None`. *Mitigation:* this is an improvement
  (empty string and null should be equivalent for optional fields); no
  known client depends on storing empty strings.

## Migration Plan

1. **Theme**: one-line change in `layout.tsx`. Deploy.
2. **Password toggle**: copy pattern from login to register. Deploy.
3. **Subject group code**: backend normalization (2 lines). Deploy.
4. **Required markers**: create `FormLabelRequired`, sweep all forms. Deploy
   (can be incremental — one form group at a time).

## Open Questions

- Should the required-field asterisk convention be documented in
  `apps/web/CONVENTIONS.md`? Lean: yes.
- Are there optional string fields OTHER than subject group code that have
  the same empty-string bug? If so, consider normalizing at a shared
  deserialization layer rather than per-handler. Lean: audit during
  implementation; for now just fix the reported bug.
