# Login Password Visibility Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract a reusable `PasswordInput` UI component with built-in password visibility toggle and integrate it into the login page.

**Architecture:** Create a `PasswordInput` component wrapping standard HTML input with a right-aligned toggle button that toggles `showPassword` state and provides `aria-label` / `title` accessibility attributes. Replace the custom input wrapper in `apps/web/src/app/login/page.tsx` with `PasswordInput`.

**Tech Stack:** React 19, Next.js, Lucide Icons (`Eye`, `EyeOff`, `Lock`), Vitest, `@testing-library/react`.

## Global Constraints

- Component must use `React.forwardRef<HTMLInputElement, PasswordInputProps>` for full `react-hook-form` compatibility.
- Accessible toggle button with dynamic `aria-label` and `title` (`"Lihat password"` / `"Sembunyikan password"`).
- `type="button"` on the toggle button to prevent triggering form submit.

---

### Task 1: Create `PasswordInput` Component and Unit Tests

**Files:**
- Create: `apps/web/src/components/ui/password-input.tsx`
- Create: `apps/web/__tests__/password-input.test.tsx`

**Interfaces:**
- Produces: `PasswordInput` component (`export { PasswordInput, type PasswordInputProps }`)
```tsx
export interface PasswordInputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  leftIcon?: React.ReactNode;
}
```

- [ ] **Step 1: Write the failing unit test for `PasswordInput`**

Create `apps/web/__tests__/password-input.test.tsx`:
```tsx
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { PasswordInput } from "@/components/ui/password-input";

describe("PasswordInput", () => {
  it("renders with type password initially and toggles visibility on button click", async () => {
    const user = userEvent.setup();
    render(<PasswordInput placeholder="Enter password" />);

    const input = screen.getByPlaceholderText("Enter password") as HTMLInputElement;
    expect(input.type).toBe("password");

    const toggleBtn = screen.getByRole("button", { name: "Lihat password" });
    expect(toggleBtn).toBeInTheDocument();
    expect(toggleBtn).toHaveAttribute("title", "Lihat password");

    await user.click(toggleBtn);

    expect(input.type).toBe("text");
    const hideBtn = screen.getByRole("button", { name: "Sembunyikan password" });
    expect(hideBtn).toBeInTheDocument();
    expect(hideBtn).toHaveAttribute("title", "Sembunyikan password");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/web && pnpm test __tests__/password-input.test.tsx`
Expected: FAIL with module `@/components/ui/password-input` not found.

- [ ] **Step 3: Write implementation of `PasswordInput`**

Create `apps/web/src/components/ui/password-input.tsx`:
```tsx
"use client";

import * as React from "react";
import { Eye, EyeOff } from "lucide-react";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";

export interface PasswordInputProps
  extends React.InputHTMLAttributes<HTMLInputElement> {
  leftIcon?: React.ReactNode;
}

const PasswordInput = React.forwardRef<HTMLInputElement, PasswordInputProps>(
  ({ className, leftIcon, disabled, ...props }, ref) => {
    const [showPassword, setShowPassword] = React.useState(false);
    const toggleLabel = showPassword ? "Sembunyikan password" : "Lihat password";

    return (
      <div className="relative w-full">
        {leftIcon && (
          <div className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground">
            {leftIcon}
          </div>
        )}
        <input
          type={showPassword ? "text" : "password"}
          ref={ref}
          disabled={disabled}
          className={cn(
            "flex h-10 w-full rounded-md border border-input bg-background py-2 text-sm ring-offset-background placeholder:text-muted-foreground/40 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50",
            leftIcon ? "pl-10 pr-10" : "pl-3 pr-10",
            className,
          )}
          {...props}
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          disabled={disabled}
          onClick={() => setShowPassword((prev) => !prev)}
          aria-label={toggleLabel}
          title={toggleLabel}
          className="absolute right-1 top-1/2 h-8 w-8 -translate-y-1/2 text-muted-foreground hover:text-foreground"
        >
          {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
        </Button>
      </div>
    );
  },
);

PasswordInput.displayName = "PasswordInput";

export { PasswordInput };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/web && pnpm test __tests__/password-input.test.tsx`
Expected: PASS.

---

### Task 2: Refactor Login Page to Use `PasswordInput`

**Files:**
- Modify: `apps/web/src/app/login/page.tsx:311-330`

**Interfaces:**
- Consumes: `PasswordInput` from `@/components/ui/password-input`

- [ ] **Step 1: Replace manual relative wrapper with `PasswordInput` in `apps/web/src/app/login/page.tsx`**

Import `PasswordInput`:
```tsx
import { PasswordInput } from "@/components/ui/password-input";
```

Replace lines 311-330:
```tsx
<FormControl>
  <PasswordInput
    leftIcon={<Lock className="h-4 w-4" />}
    autoComplete="current-password"
    {...field}
  />
</FormControl>
```

Also remove unused state `const [showPassword, setShowPassword] = React.useState(false);` if present in `LoginForm`.

- [ ] **Step 2: Run all web unit tests to verify no regressions**

Run: `cd apps/web && pnpm test`
Expected: ALL PASS.
