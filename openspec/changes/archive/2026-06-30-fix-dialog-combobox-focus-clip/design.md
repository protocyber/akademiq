## Context

Three Radix Popover-based combobox components are used inside Radix Dialogs across the academic-ops screens. Each is broken in a complementary way:

| Component | File | Portal? | Clipping | Search focus |
|---|---|---|---|---|
| `MultiSelect` (bug #3, "tambah penugasan") | `multi-select.tsx` | yes | fixed | **broken** |
| `QueryCombobox` (bug #4, "hubungkan akun") | `query-combobox.tsx` | no | **broken** | works |
| `QueryMultiSelect` (bug #5, "roster") | `query-multi-select.tsx` | no | **broken** | works |

`MultiSelect` wraps its `PopoverPrimitive.Content` in a Portal and sets `modal={false}`, but also calls `onOpenAutoFocus={(e) => e.preventDefault()}` — this prevents the popover from focusing its content, so the `CommandInput` never receives focus. `QueryCombobox` and `QueryMultiSelect` intentionally skip the Portal (a comment in `query-combobox.tsx:3-9` explains that portaling made the input unfocusable) and render `PopoverPrimitive.Content` inline — which the Dialog's `overflow`/clipping context truncates.

The underlying tension is Radix Dialog's `FocusScope` (trap) versus a Popover that needs to hold focus on its search input. Both halves of the workaround have a real failure mode; neither component is correct.

## Goals / Non-Goals

**Goals:**
- Make all three combobox components work correctly inside a Dialog: not clipped, and the search input is focusable and typeable.
- Apply one consistent strategy across all three (and any future Dialog-rendered combobox), not three bespoke fixes.
- Add regression tests so this does not regress.

**Non-Goals:**
- Replacing Radix Popover/Dialog or the shadcn combobox primitives.
- Changing combobox behavior outside Dialogs (the page-level usage is unaffected).
- Restyling the dropdowns.

## Decisions

### Decision 1: Portal + correct focus handling, uniformly
**Choice:** All three components render `PopoverPrimitive.Content` via `PopoverPrimitive.Portal` (fixes clipping) and MUST allow the popover to focus its `CommandInput` on open. `MultiSelect`'s `onOpenAutoFocus` preventDefault is removed. `QueryCombobox`/`QueryMultiSelect` gain the Portal wrapper.

**Rationale:** Clipping is solved only by portaling out of the Dialog's clipping ancestor. The focus problem (the reason the portal was originally removed) is solved by letting the popover's default open-focus run, which focuses the first focusable descendant — the `CommandInput`. The original "unfocusable inside portal" symptom was caused by the interaction of `modal={false}` + the Dialog's FocusScope reclaiming focus; removing the preventDefault and verifying the Radix focus composition resolves it.

**Alternatives considered:**
- *Keep no-Portal, fix clipping with CSS (`overflow: visible`, high z-index).* Fragile — depends on every Dialog ancestor's overflow; breaks when dialog scrolls. Rejected.
- *Render the dropdown as a sibling of the Dialog (manual portal to `document.body`).* Reimplementing what `PopoverPrimitive.Portal` already does. Rejected.

### Decision 2: Extract a shared focus/portal convention (helper if needed)
**Choice:** If the focus fix is non-trivial (e.g., requires coordinating `modal`, `onOpenAutoFocus`, or a `FocusScope` boundary), extract it into a small shared helper or a documented convention applied identically to all three, rather than copy-pasting fragile props three times.

**Rationale:** Three components with the same fragile Radix prop cocktail is a maintenance hazard. A single source of truth prevents drift (which is how this bug was born — two divergent workarounds).

### Decision 3: Verify against the installed Radix version before finalizing
**Choice:** The exact prop combination (Portal + default open-focus, possibly `modal` adjustment) MUST be validated against the installed `@radix-ui/react-popover` / `@radix-ui/react-dialog` versions, since focus-trap behavior has changed across Radix releases. The implementation task includes a manual + automated verification step.

**Rationale:** Radix focus semantics are version-sensitive; guessing the prop combo risks re-introducing one of the two halves. A quick spike on the real versions is cheaper than a third broken workaround.

## Risks / Trade-offs

- **[Focus fix is Radix-version-dependent]** → Mitigated by Decision 3 (verify on installed versions) and the regression tests.
- **[Keyboard interaction regressions (Tab/Escape/restore focus to trigger)]** → The tests MUST cover Escape-to-close and focus-return, not just type-to-search.
- **[Cross-browser focus quirks]** → Verify in Chromium and Firefox at minimum; the original bug was reported on Chrome/macOS.
- **[Other Dialogs using these components get behavior change]** → Desired (they were latently broken too); not a risk, a benefit.

## Migration Plan

1. Spike the correct Portal+focus prop combo on one component (`MultiSelect`) against the installed Radix versions; confirm search focus + no clip.
2. Apply the identical fix to `QueryCombobox` and `QueryMultiSelect`; extract the shared helper if the combo is non-trivial.
3. Add the regression tests for all three.
4. Manually verify the three dialogs ("tambah penugasan", "hubungkan akun", "roster") end-to-end.
5. No data migration, no backend deploy, no coordination — frontend-only, independently shippable.

## Open Questions

- Exact Radix prop combination for focus (confirm during the implementation spike per Decision 3).
- Whether the shared helper should also cover `QuerySelect`/`Select` (the `select.tsx` primitive already portals and is not reported broken) — likely no, but confirm none of its Dialog consumers clip.
