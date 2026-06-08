## Context

The current `apps/web` project is a Next.js application using Tailwind CSS for styles, and a set of custom wrappers in `src/components/ui` that directly use Radix UI primitives. We need to standardize on `shadcn/ui` configured with the Stitch design system (Emerald Nocturne and EduCore Narrative) to build a consistent and highly premium developer-friendly component library.

## Goals / Non-Goals

**Goals:**
- Install shadcn/ui in `apps/web`.
- Configure `tailwind.config.ts` and `src/app/globals.css` to map CSS variables matching the Emerald Nocturne and EduCore Narrative design tokens (background, primary, surface containers).
- Ensure existing pages (login, register, dashboard, settings modules) use the new shadcn components.
- Configure Google Fonts pairing (Plus Jakarta Sans and Inter) in the app layout and Tailwind theme configuration.
- Implement mathematical border radius scaling where `--radius: 0.5rem` is the base token.
- Keep the design premium, responsive, and aesthetically pleasing.

**Non-Goals:**
- Modifying backend endpoints, query/mutation hooks, or schema validation rules.
- Introducing unrelated features or routes.

## Decisions

- **Decision 1: HSL Variables for Light & Dark Themes**: We will map the colors from **EduCore Narrative** into `:root` (light mode) and **Emerald Nocturne** into `.dark` (dark mode) as HSL values inside `src/app/globals.css`.
- **Decision 2: Font Pairing (Plus Jakarta Sans & Inter)**: We will load `Plus_Jakarta_Sans` and `Inter` via Next.js `next/font/google` inside `src/app/layout.tsx` and configure them in `tailwind.config.ts` under `fontFamily.sans` and `fontFamily.display`.
- **Decision 3: Border Radius Scaling**: We will define border radius tokens in `tailwind.config.ts` relative to `--radius` (which is set to `0.5rem` / `8px`):
  * `rounded-md`: `var(--radius)` (8px - for standard elements like buttons and inputs)
  * `rounded-lg`: `calc(2 * var(--radius))` (16px - for card containers in dark mode)
  * `rounded-xl`: `calc(3 * var(--radius))` (24px - for card containers in light mode)

## Risks / Trade-offs

- **[Risk] Visual layout breakages during refactoring** → **Mitigation**: Perform systematic component replacements page-by-page. Verify form validation with react-hook-form is properly handled by the new Form component wrapper.
- **[Risk] Font configuration issues** → **Mitigation**: Ensure Plus Jakarta Sans is imported and used as the default sans-serif font family.
