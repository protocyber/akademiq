## 1. Setup and Preparation

- [x] 1.1 Verify HSL variables and custom font loading configuration inside `tailwind.config.ts` and `globals.css`

## 2. Refactor Login View

- [x] 2.1 Restructure `apps/web/src/app/login/page.tsx` to implement the split-pane layout
- [x] 2.2 Rebuild the login credentials form using shadcn `<Form>` controllers and `<Input>` fields with Lucide icons

## 3. Refactor Dashboard View

- [x] 3.1 Implement a dashboard sidebar navigation layout utilizing shadcn components
- [x] 3.2 Refactor `apps/web/src/app/dashboard/page.tsx` to use the sidebar layout and render stats cards with shadcn `<Card>` components
- [x] 3.3 Style module active/inactive indicators using shadcn `<Badge>` components

## 4. Refactor Step Registration View

- [x] 4.1 Refactor `apps/web/src/app/register/register-client.tsx` to use shadcn `<Card>`, `<Form>` controllers, and step circles

## 5. Verification and Tests

- [x] 5.1 Run types checking and verify compiler passes
- [x] 5.2 Run Vitest unit tests and Playwright E2E tests to verify zero regressions
