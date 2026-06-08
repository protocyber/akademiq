---
name: EduCore Narrative
colors:
  surface: '#f8f9ff'
  surface-dim: '#cbdbf5'
  surface-bright: '#f8f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#eff4ff'
  surface-container: '#e5eeff'
  surface-container-high: '#dce9ff'
  surface-container-highest: '#d3e4fe'
  on-surface: '#0b1c30'
  on-surface-variant: '#3c4a42'
  inverse-surface: '#213145'
  inverse-on-surface: '#eaf1ff'
  outline: '#6c7a71'
  outline-variant: '#bbcabf'
  surface-tint: '#006c49'
  primary: '#006c49'
  on-primary: '#ffffff'
  primary-container: '#10b981'
  on-primary-container: '#00422b'
  inverse-primary: '#4edea3'
  secondary: '#565e74'
  on-secondary: '#ffffff'
  secondary-container: '#dae2fd'
  on-secondary-container: '#5c647a'
  tertiary: '#5c5f61'
  on-tertiary: '#ffffff'
  tertiary-container: '#a0a3a5'
  on-tertiary-container: '#36393b'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#6ffbbe'
  primary-fixed-dim: '#4edea3'
  on-primary-fixed: '#002113'
  on-primary-fixed-variant: '#005236'
  secondary-fixed: '#dae2fd'
  secondary-fixed-dim: '#bec6e0'
  on-secondary-fixed: '#131b2e'
  on-secondary-fixed-variant: '#3f465c'
  tertiary-fixed: '#e0e3e5'
  tertiary-fixed-dim: '#c4c7c9'
  on-tertiary-fixed: '#191c1e'
  on-tertiary-fixed-variant: '#444749'
  background: '#f8f9ff'
  on-background: '#0b1c30'
  surface-variant: '#d3e4fe'
typography:
  headline-xl:
    fontFamily: Plus Jakarta Sans
    fontSize: 36px
    fontWeight: '700'
    lineHeight: 44px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 36px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-sm:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  label-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 40px
---

## Brand & Style
The design system is anchored in **Modern Corporate** principles with a focus on high-utility SaaS aesthetics. The brand personality is efficient, dependable, and optimistic, designed to reduce the cognitive load on administrators and educators.

The visual style leverages a "Soft Professionalism"—combining the rigor of enterprise software with the approachability of modern consumer apps. It utilizes heavy whitespace, a restricted color palette, and high-quality typography to ensure that complex data remains legible and actionable. The emotional response should be one of "calm control," moving away from the cluttered, legacy feel of traditional educational software toward a streamlined, task-oriented environment.

## Colors
This design system utilizes a high-clarity light mode palette to maximize readability in data-heavy environments.

- **Primary (Emerald Green):** Used for primary actions, active navigation states, and success indicators. It provides a vibrant, optimistic "pulse" to the UI.
- **Secondary (Dark Slate):** Reserved for primary text, headings, and iconography to ensure maximum contrast and an authoritative feel.
- **Surface (Light Gray/White):** A tiered system of `#FFFFFF` for primary cards and `#F8FAFC` for background canvases to create subtle depth.
- **Neutral (Slate Gray):** Used for secondary text, borders, and breadcrumbs to establish a clear visual hierarchy without competing for attention.

## Typography
The typography strategy pairs **Plus Jakarta Sans** for headlines with **Inter** for body and interface text.

- **Headlines:** Plus Jakarta Sans provides a friendly, contemporary character that softens the "corporate" edge of the SaaS. Use it for page titles, section headers, and card titles.
- **Body & Labels:** Inter is used for its exceptional legibility in data tables and forms. Its neutral, systematic nature ensures that long-form information is processed without distraction.
- **Hierarchy:** Use weight over color to distinguish hierarchy. Labels should be slightly tracked out and bolded when used for small caps metadata.

## Layout & Spacing
The layout follows a **Fixed-Fluid Hybrid** model. The sidebar navigation remains fixed, while the main content area utilizes a fluid 12-column grid system with a maximum width of 1440px to prevent excessive line lengths on ultra-wide monitors.

- **Grid:** Use a 24px gutter for desktop and 16px for mobile. 
- **Spacing Rhythm:** All spacing must be a multiple of the 4px base unit. 24px (lg) is the standard padding for cards and containers to maintain a spacious, breathable feel.
- **Mobile Reflow:** On mobile devices, cards stack vertically, and horizontal margins shrink to 16px. Complex data tables should implement horizontal scrolling with a fixed first column (e.g., Student Name).

## Elevation & Depth
Depth in the design system is achieved through **Tonal Layering** supplemented by **Ambient Shadows**. 

1. **Surface Level 0 (Canvas):** `#F8FAFC` (Slate 50). This is the foundation layer.
2. **Surface Level 1 (Cards):** `#FFFFFF` with a 1px border of `#E2E8F0` and a very soft, diffused shadow (`0px 4px 12px rgba(0, 0, 0, 0.03)`).
3. **Surface Level 2 (Modals/Popovers):** `#FFFFFF` with a more pronounced shadow (`0px 12px 32px rgba(0, 0, 0, 0.08)`) to pull the element forward.

Avoid harsh blacks; shadows should be tinted with the secondary color (Slate) to maintain a natural, cohesive appearance.

## Shapes
The design system employs a **Rounded** shape language to promote a friendly and modern user experience.

- **Standard Elements:** Buttons, inputs, and small widgets use a `0.5rem` (8px) radius.
- **Containers:** Content cards and main navigation containers use `rounded-xl` (1.5rem / 24px) to create a soft, distinct containment area.
- **Interactive States:** Focus rings should follow the curvature of the element with a 2px offset.

## Components
- **Buttons:** Primary buttons use the Emerald Green background with white text. Hover states should darken the green by 10%. Secondary buttons use a ghost style with a Slate 200 border.
- **Cards:** Cards are the primary organizational unit. They must feature `rounded-xl` corners, a white background, and the Level 1 elevation shadow. Headers within cards should have a subtle bottom border.
- **Data Tables:** Tables should be "borderless" with light horizontal separators (`#F1F5F9`). Use `body-sm` for row content and `label-md` for headers. The active row should have a subtle Emerald Green left-border accent.
- **Input Fields:** Use a Slate 200 border that transitions to Emerald Green on focus. Labels must always be visible (no placeholder-only forms).
- **Chips:** Used for status (e.g., "Active", "Absent"). Use a low-opacity version of the status color for the background (e.g., Emerald Green at 10% opacity for "Active") with full-opacity text.
- **Navigation:** The vertical sidebar should use the Dark Slate color for the background, with the Emerald Green used strictly for the "Active" indicator (usually a thick left-side bar or a high-contrast pill).