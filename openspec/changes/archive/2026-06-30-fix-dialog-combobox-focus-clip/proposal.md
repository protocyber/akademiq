## Why

Three dialogs that use Combobox-style controls are broken in complementary ways, all rooted in the same conflict between Radix Dialog's focus trap and Radix Popover-based comboboxes. The "tambah penugasan" dialog's search input cannot receive focus; the "hubungkan akun" and "roster" dialogs' dropdowns are clipped by the dialog wrapper. A developer comment in `query-combobox.tsx` documents the dilemma: portaling the popover (fixes clipping) makes the search input unfocusable, while skipping the portal (fixes focus) reintroduces clipping. The two existing workarounds each solve only half the problem, and the third component inherits the clipping half. One root cause, three broken call sites.

## What Changes

- **Standardize all Combobox-in-Dialog components on one focus+portal strategy.** The three affected components — `MultiSelect`, `QueryCombobox`, and `QueryMultiSelect` — MUST render their popover content via a Portal (eliminating clipping) AND manage focus so the search input is focusable inside an open Dialog (eliminating the focus-steal). *(Frontend, `components/ui/*.tsx`.)*
- **Remove the focus-killing `onOpenAutoFocus` preventDefault.** `MultiSelect` currently calls `event.preventDefault()` on the popover's open-auto-focus, which is what stops the search input from receiving focus. The fix MUST allow the popover to focus its content (the `CommandInput`) while composing correctly with the Dialog's focus scope. *(Frontend.)*
- **Verify the Dialog/Popover focus composition.** Confirm against the installed Radix version that a portaled Popover inside a Dialog can hold focus on its `CommandInput` (this may require the Popoper to opt into the Dialog's `FocusScope` boundary or set `modal` appropriately). The chosen approach MUST be applied identically to all three components so behavior is consistent. *(Frontend, possibly a shared helper.)*
- **Regression coverage.** Add a test harness (Vitest + Testing Library / Playwright) that renders each combobox inside a Dialog and asserts (a) the dropdown is not clipped and (b) the search input receives focus and accepts typing. *(Frontend tests.)*

## Capabilities

### New Capabilities
- `web-dialog-controls`: behavior of Combobox/Popover-based controls rendered inside Radix Dialogs (focus and clipping rules)

### Modified Capabilities
<!-- None — this is a new cross-cutting UI behavior capability. -->

## Impact

- **Frontend (`apps/web/src/components/ui/`)**: `multi-select.tsx` (remove `onOpenAutoFocus` preventDefault; ensure portal+focus), `query-combobox.tsx` (add Portal; ensure focus), `query-multi-select.tsx` (add Portal; ensure focus). Possibly extract a shared `useComboboxInDialog` focus helper if the fix is non-trivial.
- **No backend changes.** No API or data-model impact.
- **Consumers**: the three academic-ops dialogs ("tambah penugasan", "hubungkan akun", "roster") and any other Dialog that renders these components benefit automatically.
- **Tests**: new component tests asserting focus + non-clipping inside a Dialog for each of the three components.
- **Risk**: focus-management changes can have subtle cross-browser behavior; verify with the installed Radix UI version and test keyboard interaction (Tab, Escape, type-to-search).
