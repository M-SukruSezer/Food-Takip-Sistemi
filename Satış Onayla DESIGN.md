---
name: Retail Operations System
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
  on-surface-variant: '#3e4947'
  inverse-surface: '#213145'
  inverse-on-surface: '#eaf1ff'
  outline: '#6e7977'
  outline-variant: '#bdc9c6'
  surface-tint: '#006a63'
  primary: '#005c55'
  on-primary: '#ffffff'
  primary-container: '#0f766e'
  on-primary-container: '#a3faef'
  inverse-primary: '#80d5cb'
  secondary: '#316858'
  on-secondary: '#ffffff'
  secondary-container: '#b5efda'
  on-secondary-container: '#376e5e'
  tertiary: '#005e3f'
  on-tertiary: '#ffffff'
  tertiary-container: '#007952'
  on-tertiary-container: '#99ffcd'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#9cf2e8'
  primary-fixed-dim: '#80d5cb'
  on-primary-fixed: '#00201d'
  on-primary-fixed-variant: '#00504a'
  secondary-fixed: '#b5efda'
  secondary-fixed-dim: '#99d2be'
  on-secondary-fixed: '#002018'
  on-secondary-fixed-variant: '#155041'
  tertiary-fixed: '#6ffbbe'
  tertiary-fixed-dim: '#4edea3'
  on-tertiary-fixed: '#002113'
  on-tertiary-fixed-variant: '#005236'
  background: '#f8f9ff'
  on-background: '#0b1c30'
  surface-variant: '#d3e4fe'
typography:
  display-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.015em
  headline-md:
    fontFamily: Plus Jakarta Sans
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Plus Jakarta Sans
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
  body-lg:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-lg:
    fontFamily: Inter
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.01em
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.03em
  numeric-metric:
    fontFamily: Plus Jakarta Sans
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 32px
    letterSpacing: -0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-sm: 0.75rem
  margin: 1rem
  margin-tablet: 1.5rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
---

## Brand & Style

The design system establishes a high-performance, operational mobile standard tailored for active cafe and branch retail management. It serves store managers, baristas, and inventory leads operating in fast-paced floor environments where one-handed ergonomics, rapid glanceability, and unambiguous data hierarchy are essential.

The aesthetic follows an **Enterprise Modern** philosophy—marrying rigorous utilitarian functionalism with the organic warmth of specialty coffee craftsmanship. The interface balances high data density with deliberate breathing room, avoiding visual fatigue during prolonged shifts under artificial store lighting. Key visual pillars include:

- **Operational Clarity:** High-contrast information hierarchy ensuring critical metrics (stockouts, batch expiries, live revenue in TRY) can be ingested in under 300 milliseconds.
- **Calm Authority:** Deep retail teal and forest emerald anchors convey reliability, hygiene, and premium quality, avoiding the sterile coldness of legacy POS systems.
- **Tactile Ergonomics:** Structural surfaces, tap-friendly controls, and explicit semantic feedback give managers immediate physical confidence when recording counts, approving shifts, or processing transfers on mobile hardware.

## Colors

The palette is tuned specifically for light-mode retail operation, prioritizing WCAG AAA legibility against ambient counter light and glare.

- **Primary (`#0F766E`)**: Deep retail teal serving as the core action driver, prominent interactive states, selected navigation nodes, and focused form elements.
- **Secondary (`#134E3F`)**: Deep forest pine utilized for high-prominence headers, dark operational summary cards, and brand grounding.
- **Tertiary (`#10B981`)**: Vibrant emerald reserved for active status signals, positive metrics, confirmed inventory entries, and target completion trackers.
- **Neutral (`#64748B`)**: Balanced cool slate anchoring secondary copy, deactivated states, outlines, and structural layout surfaces.

### Semantic Tiers
- **Critical / Urgent (`#EF4444`, background `#FEE2E2`):** SKT expiration alerts, zero-stock notices, reconciliation discrepancies.
- **Warning / Attention (`#F59E0B`, background `#FEF3C7`):** Impending expiration (1–2 days remaining), reorder trigger thresholds, cold-chain temperature alerts.
- **Success / Optimal (`#10B981`, background `#D1FAE5`):** Sufficient stock, shift closure validated, delivery accepted.
- **Surface Foundations:** Background canvas sits at `#F8FAFC`, card containers at `#FFFFFF`, and structural borders at `#E2E8F0`.

## Typography

Typography pairs the structural warmth of **Plus Jakarta Sans** for titles, KPIs, and operational headings with the clean utilitarian neutrality of **Inter** for dense transactional tables, lists, and instructions.

### Tabular Alignment Rules
All metrics, currency figures (₺ / TL), inventory counts, and timestamps must explicitly enable OpenType tabular lining figures (`font-variant-numeric: tabular-nums; tnum`). This guarantees decimal alignment down SKU columns and eliminates jitter during live inventory refreshes.

### Mobile Scaling Rules
Headlines on viewports under 390px scale downward to prevent multi-line card titles. `display-lg` compresses to `26px / 32px` line height, maintaining visual hierarchy while preserving the vertical fold for priority inventory tasks.

## Layout & Spacing

The layout is built on a 4px/8px incremental grid tailored for mobile handheld usage.

- **Canvas & Grids:** A 4-column fluid layout on mobile viewports (<600px) with `margin: 1rem` (16px) and `gutter: 1rem` (16px). For tablet point-of-sale displays (600px–1024px), layout shifts to an 8-column layout with `margin-tablet: 1.5rem` (24px).
- **One-Handed Thumb Zone:** High-frequency actions (scan barcode, add batch count, quick filter) are anchored within bottom sheets or sticky footer toolbars within 120px of the bottom screen edge.
- **Component Padding Density:**
  - Compact data rows use `space-sm` (8px) vertical padding.
  - Standard cards and operational modules use `space-md` (16px) internal padding.
  - Key KPI summary groups and modal sheets use `space-lg` (24px) padding.

## Elevation & Depth

Visual hierarchy uses clean tonal surfaces paired with soft, directional ambient shadows to produce a grounded physical presence suitable for dirty or fast counter usage.

- **Level 0 (Flat / Canvas):** `#F8FAFC` base application canvas. Zero elevation.
- **Level 1 (Card / Container):** `#FFFFFF` surface enclosed by a 1px structural outline of `#E2E8F0`. Shadow: `0 1px 3px rgba(15, 23, 42, 0.04), 0 1px 2px rgba(15, 23, 42, 0.02)`. Used for list items, stock balance cards, and order lists.
- **Level 2 (Interactive Floating Card / Active Row):** Raised interactive elements. Shadow: `0 4px 6px -1px rgba(15, 118, 110, 0.07), 0 2px 4px -2px rgba(15, 118, 110, 0.05)`. Subtle teal-tinted ambient occlusion ensures brand cohesion.
- **Level 3 (Sticky Nav / Bottom Sheets / Floating Barcode Trigger):** Modals, drawer controls, and quick-action triggers. Shadow: `0 10px 15px -3px rgba(15, 23, 42, 0.08), 0 4px 6px -4px rgba(15, 23, 42, 0.03)`.

## Shapes

The design system adopts a **Rounded (`2`)** baseline geometry, providing smooth, tactile contours while preserving architectural discipline across dense grids.

- **Base Radius (0.5rem / 8px):** Small badges, inputs, toggle buttons, inner metric chips.
- **Card & Surface Radius (`rounded-lg`, 1rem / 16px):** Primary container cards, modal dialogs, bottom action cards.
- **Hero & Bottom Sheet Radius (`rounded-xl`, 1.5rem / 24px):** Bottom sheet top rims, sticky modal frames.
- **Pill Geometry (9999px):** Status chips, notification indicator dots, and quick avatar status frames.

## Components

### Buttons & Quick Actions
- **Primary Action:** Solid `#0F766E` background with white text, 48px minimum height for thumb tap accuracy, `rounded-lg` (16px) corners. Active state scales subtly down (`scale(0.98)`). Left-aligned SVG icon slot with 8px spacing.
- **Secondary Action:** Outlined with 1.5px `#0F766E` border, `#FFFFFF` background, `#0F766E` text.
- **Destructive/Urgent Action:** Light tint `#FEE2E2` fill, `#EF4444` bold label for critical discards or batch write-offs.

### Chips & Status Badges
- **Status Pills:** Compact 24px–28px height, `rounded-full` shape. Constructed with a 6px status dot alongside semibold text.
  - *Sufficient / Satışta:* `#D1FAE5` fill, `#065F46` label, `#10B981` dot.
  - *Expiring Soon / Kritik:* `#FEF3C7` fill, `#92400E` label, `#F59E0B` dot.
  - *Out of Stock / SKT Geçti:* `#FEE2E2` fill, `#991B1B` label, `#EF4444` dot.

### Cards & Operational Rows
- **Stock Card:** Border-radius 16px, white surface, 1px `#E2E8F0` border. Top row contains SKU title and category chip; center row contains prominent metric count and expiry countdown; bottom row displays quick inline action buttons (+ / - adjustments).

### Form & Number Inputs
- **Field Ergonomics:** 48px height, 1px `#CBD5E1` outline, `#F8FAFC` background shifting to `#FFFFFF` on focus with a 2px `#0F766E` ring. Clear numerical keypads for stock count entries with automated decimal handling for bulk bean weights (kg/gr).

### Header & Manager Profile Strip
- **Store Manager Profile Chip:** Compact top app bar module featuring the location badge ("Düzce Merkez"), current shift lead initials, live sync state, and quick-alert bell badge with urgent counter indicator.