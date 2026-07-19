---
name: Botanical Modern
colors:
  surface: '#f9f9f8'
  surface-dim: '#d9dad9'
  surface-bright: '#f9f9f8'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f4f3'
  surface-container: '#edeeed'
  surface-container-high: '#e7e8e7'
  surface-container-highest: '#e1e3e2'
  on-surface: '#191c1c'
  on-surface-variant: '#414844'
  inverse-surface: '#2e3131'
  inverse-on-surface: '#f0f1f0'
  outline: '#717973'
  outline-variant: '#c1c8c2'
  surface-tint: '#3f6653'
  primary: '#012d1d'
  on-primary: '#ffffff'
  primary-container: '#1b4332'
  on-primary-container: '#86af99'
  inverse-primary: '#a5d0b9'
  secondary: '#3e6750'
  on-secondary: '#ffffff'
  secondary-container: '#bdeacd'
  on-secondary-container: '#426b54'
  tertiary: '#500c00'
  on-tertiary: '#ffffff'
  tertiary-container: '#741b04'
  on-tertiary-container: '#ff8364'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#c1ecd4'
  primary-fixed-dim: '#a5d0b9'
  on-primary-fixed: '#002114'
  on-primary-fixed-variant: '#274e3d'
  secondary-fixed: '#c0edd0'
  secondary-fixed-dim: '#a4d1b4'
  on-secondary-fixed: '#002112'
  on-secondary-fixed-variant: '#264f39'
  tertiary-fixed: '#ffdad2'
  tertiary-fixed-dim: '#ffb4a2'
  on-tertiary-fixed: '#3c0700'
  on-tertiary-fixed-variant: '#83260e'
  background: '#f9f9f8'
  on-background: '#191c1c'
  surface-variant: '#e1e3e2'
typography:
  display-lg:
    fontFamily: Literata
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Literata
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Literata
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
  headline-md:
    fontFamily: Literata
    fontSize: 24px
    fontWeight: '500'
    lineHeight: 32px
  body-lg:
    fontFamily: Work Sans
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Work Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-md:
    fontFamily: Work Sans
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.05em
  label-sm:
    fontFamily: Work Sans
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
  lg: 32px
  xl: 48px
  container-margin: 20px
  gutter: 16px
---

## Brand & Style

The design system is centered on the "Botanical Modern" aesthetic, blending the precision of high-end technology with the organic warmth of nature. It is designed for plant enthusiasts who seek professional-grade horticultural advice through a clean, approachable, and premium interface.

The visual language draws from **Modern Minimalism** and **Tactile Softness**. It prioritizes a sense of "digital greenhouse" serenity—using expansive white space, soft-focus imagery, and a color palette derived from natural landscapes. The emotional goal is to reduce the anxiety of plant care, replacing it with a feeling of calm, competence, and reliability.

## Colors

The palette is rooted in a "Forest to Soil" philosophy:
- **Primary (Forest Green):** A deep, authoritative green used for primary actions, navigation states, and brand presence. It conveys growth and expertise.
- **Secondary (Sage & Mint):** Soft, desaturated greens used for large background washes and subtle container fills. These reduce eye strain and establish the botanical atmosphere.
- **Accent (Terracotta):** A warm, earthy red used sparingly for alerts, critical care notifications (e.g., "Needs Water"), or "Action Required" states.
- **Neutrals:** A range of off-whites and soft greys that prevent the UI from feeling sterile. Pure white is reserved exclusively for elevated "Care Cards."

## Typography

The typographic system creates a "Modern Editorial" feel. 
- **Headlines:** Uses **Literata**, a refined serif that provides an authoritative, bookish, and premium quality. It should be used for page titles and section headers to establish a sophisticated hierarchy.
- **Body & Data:** Uses **Work Sans**, a highly legible and grounded sans-serif. It handles complex plant data and care instructions with clarity and professional neutrality.
- **Scaling:** On mobile devices, headline sizes should reduce slightly to maintain comfortable line lengths, while body text remains generous to ensure readability in outdoor/bright light conditions.

## Layout & Spacing

The design system utilizes a **Fluid Grid** with generous safe areas to maintain a "breathable" feel. 
- **Mobile:** A 4-column grid with 20px outside margins and 16px gutters.
- **Rhythm:** Spacing follows an 8px base unit. However, component-to-component spacing (Vertical Rhythm) should lean towards larger values (24px or 32px) to reinforce the minimalist aesthetic.
- **Alignment:** Content should be centered or left-aligned; right-alignment is reserved for specific metadata within cards.

## Elevation & Depth

Depth is achieved through **Tonal Layering** and **Ambient Shadows**, avoiding harsh contrasts.
- **Surface Hierarchy:** The base background is the "Mint/Sage" wash. Content sits on "Pure White" cards.
- **Shadows:** Use extremely soft, diffused shadows with a slight green tint (`rgba(27, 67, 50, 0.08)`) rather than pure black. This mimics natural, filtered light.
- **Interaction:** Upon press, cards should slightly "sink" (shadow reduction) or expand (subtle scale to 1.02) to provide tactile feedback without breaking the clean aesthetic.

## Shapes

The shape language is **Ultra-Soft**. 
- **Containers:** Main cards and modals use a 24px radius to feel organic and friendly.
- **Interactive Elements:** Buttons and input fields use a 16px radius.
- **Media:** Plant photography should always feature rounded corners or be contained within circular masks to avoid "sharp" digital edges that conflict with the botanical theme.

## Components

- **Buttons:** Primary buttons are solid Forest Green with white text. Secondary buttons use a ghost style with a thin green border. Tertiary buttons are text-only with the Forest Green color.
- **Plant Cards:** High-elevation white cards containing a plant image, its common name in Literata, and a status "pill" (e.g., "Thriving").
- **Status Chips:** Use secondary mint backgrounds with Forest Green text for positive statuses, and pale terracotta backgrounds with dark terracotta text for warnings.
- **Input Fields:** Soft grey backgrounds with 16px rounding and a Forest Green focus border.
- **Icons:** Thin-line (1px or 1.5px stroke) botanical icons. Avoid solid fills unless used for active navigation states.
- **Progress Bars:** Used for "Health Bars" or "Moisture Levels," utilizing a soft green-to-deep-green gradient.