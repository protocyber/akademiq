## 1. Setup and Installation

- [x] 1.1 Install HSL/Tailwind dependencies (e.g. `tailwindcss-animate`) in `apps/web/package.json`
- [x] 1.2 Verify `apps/web/components.json` layout configuration

## 2. Design System and Theme Setup

- [x] 2.1 Map HSL variables for EduCore Narrative (light) and Emerald Nocturne (dark) in `apps/web/src/app/globals.css`
- [x] 2.2 Configure Next.js font loading for Plus Jakarta Sans and Inter inside `apps/web/src/app/layout.tsx`
- [x] 2.3 Configure `apps/web/tailwind.config.ts` with the new HSL variables, font family mappings, and scaled border radius tokens

## 3. UI Component Migration

- [x] 3.1 Prepare/install shadcn components: Switch, Button, Form, Card, Tooltip, Input, Alert, Skeleton
- [x] 3.2 Update `apps/web/src/app/login/page.tsx` to use the migrated components
- [x] 3.3 Update `apps/web/src/app/register/register-client.tsx` to use the migrated components
- [x] 3.4 Update `apps/web/src/app/settings/modules/page.tsx` to use the migrated components
- [x] 3.5 Update `apps/web/src/app/dashboard/page.tsx` to use the migrated components

## 4. Testing and Verification

- [x] 4.1 Run types check and verify compiler passes
- [x] 4.2 Run project test suites to ensure everything works
