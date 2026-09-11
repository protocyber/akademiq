# Design Spec: Reusable PasswordInput Component & Login Page Integration

Date: 2026-09-02
Topic: Password Input Visibility Toggle Button

## 1. Overview
This specification details the creation of a reusable `PasswordInput` UI component in `apps/web/src/components/ui/password-input.tsx` and its integration into the login page (`apps/web/src/app/login/page.tsx`).

## 2. Component Design (`PasswordInput`)
- **File**: `apps/web/src/components/ui/password-input.tsx`
- **Interface**: Extends `React.InputHTMLAttributes<HTMLInputElement>` (`InputProps`), accepting optional `leftIcon?: React.ReactNode`.
- **State**: `showPassword` (`boolean`, initial `false`).
- **Icons**: Uses Lucide icons `Eye` and `EyeOff`.
- **Accessibility**:
  - `type="button"` on the toggle button to prevent triggering form submission.
  - `aria-label`: `"Sembunyikan password"` when visible, `"Lihat password"` when hidden.
  - `title`: `"Sembunyikan password"` when visible, `"Lihat password"` when hidden.
- **Ref Forwarding**: Implements `React.forwardRef<HTMLInputElement, PasswordInputProps>` for compatibility with `react-hook-form` and direct DOM refs.

## 3. Login Page Integration
- **File**: `apps/web/src/app/login/page.tsx`
- **Changes**:
  - Import `PasswordInput` from `@/components/ui/password-input`.
  - Replace manual relative `Input` wrapper with `PasswordInput`.
  - Remove redundant local `showPassword` state from `LoginForm`.

## 4. Testing Plan
- **File**: `apps/web/__tests__/password-input.test.tsx`
- **Test Scenarios**:
  - Initial render has `type="password"`.
  - Clicking toggle button switches `type` to `"text"` and updates `aria-label`/`title`.
  - Input handles text changes and ref forwarding properly.
