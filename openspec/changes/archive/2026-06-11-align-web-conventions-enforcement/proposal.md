## Why

`apps/web/CONVENTIONS.md` already mandates the two rules we want:

1. **§1** — all interactive UI composed from shadcn/ui primitives; native
   `<button>/<input>/<select>/<textarea>` forbidden in `src/app/`,
   `src/components/features/`, `src/components/pages/` (enforced by ESLint
   `react/forbid-elements`).
2. **§2 / §5** — all data access through TanStack Query; raw `fetch()`
   confined to `lib/api/client.ts`.

The rules exist, but an audit found the implementation drifted around them,
some native controls were never migrated, and in two places the rules
reference machinery that was never built. This change makes the conventions
true: **every native form element in `apps/web` is replaced with a shadcn
primitive**, and query-bound selects show a circular loading indicator while
their data loads.

## Audit findings (complete native-element inventory)

### Rule 1 — shadcn / no native controls

| Element | Sites | Resolution |
|---|---|---|
| native `<select>` (via `SelectInput`) | `curriculum:150`, `grading-policy:109`, `years:206`, `YearPicker` (`academic-settings:223`) | shadcn `Select` |
| native `<input type="checkbox">` (bare, not RHF-wired, native `<label>`) | `login:237` | shadcn `Checkbox` + `Label` |
| `<Input type="date">` (native browser date picker) | `years:121` (start), `years:134` (end) | shadcn `DatePicker` (Popover + Calendar) |
| `<input type="hidden">` ×3 (RHF id plumbing) | `grading-policy:88`, `curriculum:158`, `class-templates:76` | remove; bind via RHF `register`/`setValue` |
| `<Input number/email/password>`, `<Button>` | many | already shadcn — compliant |

Notable detail: **`@radix-ui/react-select@2.1.6` is already a dependency** but
no `src/components/ui/select.tsx` was ever created — the Radix package was
installed and the shadcn component step skipped, which is what drove the
`SelectInput` native-`<select>` workaround. The component files for
`Checkbox`, `Calendar`, `Popover`, and `Textarea` do not exist either.

### Rule 2 — TanStack / single fetch

- Component data access is clean: every `.refetch()` call site is a TanStack
  hook, not a raw fetch.
- **§5 contradicts the code.** It states `lib/api/client.ts` is "the only
  place `fetch()` is called", but `src/lib/query/server.ts:39` calls raw
  `fetch()` for the server-side plan-catalog prefetch (the `dehydrate` /
  `HydrationBoundary` path documented in §2).
- `useEffect` calls in settings pages sync form state / default selections;
  none perform fetching, so §2's "no useEffect fetching" holds.

### New behavior — query-bound select loading state

Today the selects pass `disabled={!curriculum.data?.length}` and go dead with
no signal while the query is in flight. The requirement: a select fed by a
TanStack query SHALL show a circular spinner (`ui/spinner.tsx`, per §3) inside
its trigger while `isLoading`, with a distinct empty state on `success` with
no rows. This behavior lives in one reusable wrapper so it cannot drift the
way `SelectInput` did.

## What Changes

- **Install shadcn primitives** into `src/components/ui/`:
  `select` (dep already present), `textarea`, `checkbox`, `calendar`,
  `popover`. Add deps `@radix-ui/react-checkbox`, `@radix-ui/react-popover`,
  `react-day-picker`, `date-fns`.
- **`QuerySelect` wrapper** (`src/components/ui/query-select.tsx` or a
  `features` helper) — wraps shadcn `Select`, accepts the query's
  `isLoading` / items / empty text, renders spinner-in-trigger + `disabled` +
  empty state. The single home for query-bound select loading.
- **Migrate native `<select>`** — 4 `SelectInput` call sites → `Select` /
  `QuerySelect`; delete `SelectInput`.
- **Migrate the checkbox** — `login:237` native `<input type="checkbox">` +
  native `<label>` → shadcn `Checkbox` + `Label`, RHF-wired.
- **Build & adopt `DatePicker`** — Popover + Calendar component; replace both
  `<Input type="date">` in `years`. DatePicker converts between the form's
  `z.string()` value (`YYYY-MM-DD`) and the Calendar's `Date` via `date-fns`.
- **Resolve hidden `<input>`s** — RHF `register`/`setValue`, no rendered
  element; drop the redundant one in `curriculum`.
- **Document the second fetch site** — reword `CONVENTIONS.md §5` to allow
  `fetch()` in `client.ts` **and** `lib/query/server.ts`.
- **Tighten ESLint** so `react/forbid-elements` genuinely guards `features/`
  (the `SelectInput` escape hatch should have been caught).

## Impact

- Affected specs: `install-shadcn` (Select, Textarea, Checkbox, DatePicker
  primitives + query-bound select loading).
- Affected code: `apps/web/src/components/ui/` (5 new primitives + wrapper),
  `years`, `curriculum`, `grading-policy`, `class-templates`, `login` pages,
  `academic-settings.tsx`, `package.json`, `.eslintrc.json`, `CONVENTIONS.md`.
- New runtime deps: `@radix-ui/react-checkbox`, `@radix-ui/react-popover`,
  `react-day-picker`, `date-fns`.
- No backend impact. Date values stay `YYYY-MM-DD` strings on the wire.
