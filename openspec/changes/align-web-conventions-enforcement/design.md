## Context

Two conventions (`apps/web/CONVENTIONS.md` §1 shadcn-only, §2/§5 TanStack +
single-fetch) are already written and partly enforced by ESLint. The audit in
`proposal.md` found the code drifted around them and that several native form
elements (select, checkbox, date) were never migrated. This document records
the decisions taken in the explore sessions that resolve each gap.

## Decisions

### D1 — Native `<select>` → install real shadcn Select (not bless the wrapper)

`SelectInput` is a styled native `<select>`. shadcn's `Select` is a Radix
popover (`Select` / `SelectTrigger` / `SelectValue` / `SelectContent` /
`SelectItem`). The Radix dependency (`@radix-ui/react-select`) is already
installed — only the component file was skipped.

**Chosen:** create `ui/select.tsx`, migrate call sites, delete `SelectInput`.
**Rejected:** moving `SelectInput` into `ui/` to legitimize it — keeps a
native control and forks "the dropdown" into two things, the exact drift §1
prevents.

RHF binding moves from `{...field}` spread (native) to controlled
`value` + `onValueChange`. The `grading-policy` site needs the most rework.

### D2 — Server prefetch fetch() is allowed, documented not refactored

`lib/query/server.ts:39` calls raw `fetch()` for SSR plan-catalog prefetch —
a different context from client `apiFetch` (no token-refresh loop, runs on the
server, feeds `dehydrate`).

**Chosen:** reword §5 to permit `fetch()` in `client.ts` **and** `server.ts`.
**Rejected:** forcing prefetch through `apiFetch` — its 401→refresh→redirect
machinery is browser-oriented and wrong on the server.

### D3 — Hidden inputs are form plumbing, removed not "shadcn-ified"

No shadcn primitive exists for a hidden field and none should. Register the
field with RHF (`register`/`setValue`) without rendering an element. Remove the
redundant hidden input in `curriculum` (value already set via `setValue`).
Clarify §1 text: the rule targets *interactive UI controls*; a hidden field is
not one.

### D4 — ESLint must actually guard features/

`SelectInput`'s native `<select>` sat in `features/` (not an override path)
with no `eslint-disable`, yet was not caught — implying lint is not gating in
practice. Verify `next lint` runs clean after migration and that `features/`
is genuinely covered, so the escape hatch cannot reopen silently.

### D5 — Query-bound select loading lives in ONE reusable wrapper

shadcn `Select` has no built-in loading prop. Rather than re-implement
spinner+disabled+empty at each of the 4 call sites (the road that produced
`SelectInput`), introduce a single `QuerySelect` wrapper.

Sketch (signature finalized at implementation):

```tsx
<QuerySelect
  isLoading={curriculum.isLoading}
  items={curriculum.data ?? []}
  getKey={(i) => i.curriculum_version_id}
  getLabel={(i) => i.name}
  value={curriculumId}
  onValueChange={setCurriculumId}
  placeholder="Pilih kurikulum"
  emptyText="Tidak ada data"
/>
```

State → trigger:
```
isLoading       → [ ⟳  Memuat…        ▾ ]   <Spinner size="sm"/> + disabled
success & empty → [ Tidak ada data    ▾ ]   disabled
success & data  → [ placeholder       ▾ ]   normal
```

Uses the existing `ui/spinner.tsx` (§3 inline-spinner tier). Static-option
selects (e.g. grading scale `0-100` / `A-E`, year status enum) use plain
`Select`, not `QuerySelect` — they have no query.

**Rejected:** a per-site `loading` convention — more repetition, drifts.

### D6 — DatePicker: Popover + Calendar, string↔Date at the boundary

`<Input type="date">` renders the browser's native picker; the form schema
stores `z.string()` (`YYYY-MM-DD`). A shadcn DatePicker (Popover trigger +
`react-day-picker` Calendar) gives a consistent cross-browser UI.

The Calendar works in `Date`; the form stays `string`. The DatePicker is the
**only** place conversion happens:
```
form value "2026-06-08" ──parseISO──▶ Date ──Calendar select──▶ Date
                                                    │
                          format(d,"yyyy-MM-dd") ◀──┘  ──▶ field.onChange(string)
```
Schema (`academic-year.ts`) is unchanged; wire format `YYYY-MM-DD` unchanged.

New deps: `@radix-ui/react-popover`, `react-day-picker`, `date-fns`.

### D7 — Checkbox: shadcn Checkbox + Label, and wire it to RHF

The login "remember device" checkbox is a bare native `<input type="checkbox">`
with a native `<label>` and **no form binding at all** — it currently does
nothing. Replace with shadcn `Checkbox` + `Label`. Decide during
implementation whether "remember device" feeds the login mutation (30-day
session) or stays presentational; if it has no backend effect yet, keep it
RHF-bound but flag the dead wiring rather than inventing an endpoint.

New dep: `@radix-ui/react-checkbox`.

## Open questions

- Is `next lint` wired into CI / a pre-commit hook? If not, the rules will
  drift again regardless of wording. (Follow-up, out of scope here.)
- Does "remember device for 30 days" have a backend contract, or is it
  currently decorative? (Affects D7 wiring.)
