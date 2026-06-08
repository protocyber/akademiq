---
name: Emerald Nocturne
colors:
  surface: '#0b1326'
  surface-dim: '#0b1326'
  surface-bright: '#31394d'
  surface-container-lowest: '#060e20'
  surface-container-low: '#131b2e'
  surface-container: '#171f33'
  surface-container-high: '#222a3d'
  surface-container-highest: '#2d3449'
  on-surface: '#dae2fd'
  on-surface-variant: '#bbcabf'
  inverse-surface: '#dae2fd'
  inverse-on-surface: '#283044'
  outline: '#86948a'
  outline-variant: '#3c4a42'
  surface-tint: '#4edea3'
  primary: '#4edea3'
  on-primary: '#003824'
  primary-container: '#10b981'
  on-primary-container: '#00422b'
  inverse-primary: '#006c49'
  secondary: '#45dfa4'
  on-secondary: '#003825'
  secondary-container: '#00bd85'
  on-secondary-container: '#00452e'
  tertiary: '#68dba9'
  on-tertiary: '#003825'
  tertiary-container: '#3eb686'
  on-tertiary-container: '#00422c'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#6ffbbe'
  primary-fixed-dim: '#4edea3'
  on-primary-fixed: '#002113'
  on-primary-fixed-variant: '#005236'
  secondary-fixed: '#68fcbf'
  secondary-fixed-dim: '#45dfa4'
  on-secondary-fixed: '#002114'
  on-secondary-fixed-variant: '#005137'
  tertiary-fixed: '#85f8c4'
  tertiary-fixed-dim: '#68dba9'
  on-tertiary-fixed: '#002114'
  on-tertiary-fixed-variant: '#005137'
  background: '#0b1326'
  on-background: '#dae2fd'
  surface-variant: '#2d3449'
typography:
  display-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
  title-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  caption:
    fontFamily: Plus Jakarta Sans
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
  base: 8px
  xs: 4px
  sm: 12px
  md: 24px
  lg: 40px
  xl: 64px
  gutter: 24px
  margin-mobile: 16px
  margin-desktop: 48px
---

## Brand & Style
This design system is built for high-performance interfaces that require prolonged focus and visual clarity. The brand personality is precise, energetic, and sophisticated, leaning into a **Modern Corporate** aesthetic with subtle **Glassmorphism** accents. 

By utilizing a deep, monochromatic dark base contrasted with a vibrant emerald accent, the UI evokes a sense of technological mastery and environmental vitality. The emotional response is one of calm confidence and streamlined efficiency, making it ideal for data-heavy SaaS or premium fintech applications.

## Colors
The palette is centered on "Emerald Green" (#10b981), optimized for accessibility against a near-black slate background. 

- **Primary:** The emerald green acts as the primary action color, used for CTA buttons, active states, and critical information markers.
- **Surface Strategy:** We utilize a "Slate" scale for neutrals to maintain a cool, professional depth. Backgrounds are set to the darkest value (#020617), while cards and navigation elements use a slightly lighter surface (#0f172a) to create perceived depth.
- **Contrast:** Text is tiered to ensure readability; primary text uses high-contrast off-white, while secondary text uses a muted slate-blue to reduce visual noise.

## Typography
The design system exclusively uses **Plus Jakarta Sans** to take advantage of its modern, geometric construction and high x-height, which ensures exceptional legibility in dark mode.

Headlines use tighter letter-spacing and bold weights to command attention. Body copy maintains a generous line height (1.5x) to prevent "haloing" effects common in light-on-dark text. For mobile devices, large display styles scale down to prevent excessive word-breaking while maintaining the font's characteristic openness.

## Layout & Spacing
The layout follows a **Fluid Grid** logic based on an 8px square system. This ensures mathematical harmony across all components.

- **Desktop:** A 12-column grid with 24px gutters and 48px outside margins. 
- **Tablet:** An 8-column grid with 24px gutters and 32px margins.
- **Mobile:** A 4-column grid with 16px gutters and 16px margins.

Spacing is applied through logical multiples of the 8px base. Internal component padding (e.g., inside a card) should typically use the `md` (24px) token to ensure content has sufficient breathing room against the dark background.

## Elevation & Depth
In this dark mode environment, depth is communicated through **Tonal Layering** and **Subtle Glows** rather than traditional black shadows.

- **Level 0 (Background):** The base layer (#020617).
- **Level 1 (Surface):** Default container color (#0f172a).
- **Level 2 (Raised):** Surfaces that sit above the main UI use a slightly lighter slate (#1e293b) and a subtle 1px inner border (10% opacity white) to define the edge.
- **Overlays:** Modals and menus utilize a backdrop blur (12px) with a semi-transparent surface to maintain context of the underlying layers.
- **Active Accents:** Elements in an active state may utilize a soft emerald outer glow (5% opacity) to signify interaction.

## Shapes
The design system employs a **Rounded** (0.5rem) shape language. This softens the high-contrast transitions between the dark surfaces and the emerald accents.

- **Standard Elements:** Buttons, input fields, and small cards use 0.5rem (8px) corners.
- **Large Containers:** Content sections and large modals use `rounded-lg` (1rem / 16px).
- **Interactive Indicators:** Small badges or tags use `rounded-xl` (1.5rem / 24px) to distinguish them from functional buttons.

## Components

- **Buttons:** Primary buttons use a solid emerald green (#10b981) background with dark navy text (#020617) for maximum contrast. Secondary buttons use a ghost style with a 1px emerald border.
- **Input Fields:** Backgrounds should be darker than the surface layer (#020617) with a 1px slate border. On focus, the border transitions to emerald green.
- **Cards:** Use the Level 1 Surface color. Provide a subtle top-border highlight in emerald for "featured" cards to draw the eye.
- **Chips/Badges:** Use a low-opacity emerald tint (10% opacity) for the background with solid emerald text to keep the UI from feeling too heavy.
- **Lists:** Items should be separated by a 1px slate-800 divider. Hover states should trigger a slight lightening of the surface color rather than a color change.
- **Checkboxes & Radios:** When checked, these components fill with the emerald primary color. Use white for the internal check/dot icon for clarity.