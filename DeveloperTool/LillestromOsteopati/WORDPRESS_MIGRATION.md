# WordPress Migration Strategy — Lillestrøm Osteopati

Manual strategy for deploying the static site content into WordPress while preserving all icons, styling, and visual consistency across every section.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Theme Installation](#theme-installation)
4. [Icon Reference (Complete)](#icon-reference-complete)
5. [Section-by-Section Deployment](#section-by-section-deployment)
   - [Navigation](#1-navigation)
   - [Hero](#2-hero)
   - [Om oss (About)](#3-om-oss-about)
   - [Osteopati](#4-osteopati)
   - [Behandlinger (Treatments)](#5-behandlinger-treatments)
   - [Prosess (Process)](#6-prosess-process)
   - [Behandlere (Staff)](#7-behandlere-staff)
   - [Forsikring (Insurance)](#8-forsikring-insurance)
   - [Bedrift (Corporate)](#9-bedrift-corporate)
   - [Priser (Pricing)](#10-priser-pricing)
   - [Kontakt (Contact)](#11-kontakt-contact)
   - [FAQ](#12-faq)
   - [Timebestilling (CTA)](#13-timebestilling-cta)
   - [Footer](#14-footer)
6. [Contact Form Setup](#contact-form-setup)
7. [Asset Checklist](#asset-checklist)
8. [Visual Consistency Rules](#visual-consistency-rules)
9. [Post-Deployment Verification](#post-deployment-verification)
10. [Remaining Work (Theme Gaps)](#remaining-work-theme-gaps)

---

## Overview

| Item | Static Site | WordPress Theme |
|------|-------------|-----------------|
| **Source** | `LillestromOsteopati/` | `LillestromOsteopatiWordPress/lillestrom-osteopati/` |
| **Architecture** | Single `index.html` + `styles.css` + `script.js` | Custom WP theme with template parts, Customizer, CPTs |
| **Icons** | Font Awesome 6.5.1 (CDN) | Font Awesome 6.5.1 (CDN) — same source |
| **Fonts** | Google Fonts: Inter + Playfair Display | Google Fonts: Inter + Playfair Display — same source |
| **CSS Variables** | Identical color palette, spacing, shadows, radii | Identical — copied into `style.css` |
| **Contact Form** | FormSubmit.co | Contact Form 7 (CF7) plugin |
| **Content Editing** | Edit HTML directly | WordPress Customizer + CPTs (Behandlere, FAQ) |

The WordPress theme (`LillestromOsteopatiWordPress/`) already contains:

- Full `style.css` with all CSS variables, component styles, and responsive breakpoints
- `header.php` + `footer.php` with WordPress hooks
- Template parts for: Hero, About, Osteopati, Behandlinger, Prosess, Behandlere
- Customizer settings for editable text fields
- Custom Post Types: `behandler` (staff) and `faq_item` (FAQ)
- Auto-population on theme activation (front page, nav menu, staff, FAQ, CF7 form)
- CF7 overrides in CSS for form styling parity

**What is NOT yet in the theme:** Forsikring, Bedrift, Priser, Kontakt, FAQ, Timebestilling/CTA, and Takk template parts.

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| WordPress | 6.0+ (tested up to 6.7) |
| PHP | 7.4+ |
| Required plugin | **Contact Form 7** (CF7) — for the contact form |
| Hosting | Domeneshop webhotell for `lillestrom-osteopati.no` |
| FTP/SFTP access | See `DEPLOY.md` for credentials |

---

## Theme Installation

### Step 1: Upload the Theme

1. ZIP the folder `LillestromOsteopatiWordPress/lillestrom-osteopati/` (the folder itself must be the ZIP root)
2. In WordPress admin: **Appearance > Themes > Add New > Upload Theme**
3. Upload the ZIP and click **Install Now**

### Step 2: Activate

1. Click **Activate** on the "Lillestrøm Osteopati" theme
2. On activation, the `lo_populate_initial_content()` function in `inc/theme-setup.php` will automatically:
   - Create the "Hjem" static front page
   - Create the "Hovedmeny" navigation menu with all anchor links
   - Create the Thomas Sewell `behandler` post with meta fields
   - Create 8 `faq_item` posts
   - Create a Contact Form 7 form (if CF7 is installed)

### Step 3: Upload Images

Upload these images to `wp-content/themes/lillestrom-osteopati/assets/images/`:

```
assets/images/
├── logo.png
├── klinikk.png
├── Behandling-T-10.jpg
├── Behandling-T-2.jpg          (optional, additional staff photo)
├── Behandling-Petter-4.jpg     (optional, additional staff photo)
├── Behandlingsrom-3.jpg        (optional, clinic room photo)
└── Gruppebilde-5.jpg           (optional, group photo)
```

> These images must be uploaded via FTP/SFTP since the theme references them with `get_template_directory_uri() . '/assets/images/...'`.

---

## Icon Reference (Complete)

All icons come from **Font Awesome 6.5.1** (CDN: `cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css`). The theme enqueues this in `functions.php` via `wp_enqueue_style()`.

### Hero Section Badges

| Icon Class | Usage | Visual |
|------------|-------|--------|
| `fas fa-user-md` | Autorisert helsepersonell | Stethoscope person |
| `fas fa-clock` | Ingen ventetid | Clock |
| `fas fa-file-medical` | Ingen henvisning nødvendig | Medical document |
| `fas fa-chevron-down` | Scroll indicator | Down arrow |

### Osteopati Branch Cards

| Icon Class | Usage | Visual |
|------------|-------|--------|
| `fas fa-bone` | Parietal osteopati | Bone |
| `fas fa-lungs` | Visceral osteopati | Lungs |
| `fas fa-brain` | Kranial osteopati | Brain |

### Treatment Cards (Behandlinger)

| Icon Class | Usage | Visual |
|------------|-------|--------|
| `fas fa-arrow-down` | Rygg- og nakkesmerter | Down arrow |
| `fas fa-head-side-virus` | Hodepine og migrene | Head with virus |
| `fas fa-running` | Idrettsskader | Running person |
| `fas fa-baby` | Barn og spedbarn | Baby |
| `fas fa-female` | Graviditet | Female figure |
| `fas fa-hand-paper` | Skulder, albue og hånd | Open hand |
| `fas fa-shoe-prints` | Kne, hofte og fot | Shoe prints |
| `fas fa-couch` | Stivhet og nedsatt funksjon | Couch |
| `fas fa-stomach` | Mage- og fordøyelsesplager | Stomach |
| `fas fa-wind` | Pustebesvær | Wind |
| `fas fa-laptop` | Kontorplager | Laptop |
| `fas fa-hand-sparkles` | Seneskjedebetennelser | Sparkle hand |

### Staff Section (Behandlere)

| Icon Class | Usage | Visual |
|------------|-------|--------|
| `fas fa-graduation-cap` | Utdanning heading | Graduation cap |
| `fas fa-stethoscope` | Faglige interesseområder heading | Stethoscope |

### Insurance Section (Forsikring)

| Icon Class | Usage | Visual |
|------------|-------|--------|
| `fas fa-info-circle` | Insurance note | Info circle |
| `fas fa-shield-alt` | Autorisert helsepersonell | Shield |

### Corporate Section (Bedrift)

| Icon Class | Usage | Visual |
|------------|-------|--------|
| `fas fa-calendar-check` | Redusert sykefravær | Calendar check |
| `fas fa-smile` | Økt trivsel | Smile |
| `fas fa-piggy-bank` | Reduserte kostnader | Piggy bank |
| `fas fa-chart-line` | Økt ytelse | Chart line |
| `fas fa-users` | Godt arbeidsmiljø | Users/people |
| `fas fa-building` | Behandling på arbeidsplassen | Building |
| `fas fa-receipt` | Fleksibel betaling | Receipt |
| `fas fa-percentage` | Skattefradrag | Percentage |
| `fas fa-exclamation-triangle` | Sykefravær statistikk | Warning triangle |

### Contact Section

| Icon Class | Usage | Visual |
|------------|-------|--------|
| `fas fa-envelope` | E-post | Envelope |
| `fas fa-map-marker-alt` | Adresse | Map pin |
| `fas fa-phone` | Telefon | Phone |
| `fas fa-paper-plane` | Send melding button | Paper plane |

### CTA / Booking

| Icon Class | Usage | Visual |
|------------|-------|--------|
| `fas fa-shield-alt` | Autorisert helsepersonell note | Shield |

### Thank You Page

| Icon Class | Usage | Visual |
|------------|-------|--------|
| `fas fa-check-circle` | Confirmation icon | Check circle |

### FAQ

| Icon Class | Usage | Visual |
|------------|-------|--------|
| `fas fa-chevron-down` | Accordion toggle | Down arrow |

---

## Section-by-Section Deployment

For each section below, verify the WordPress output matches the static site. The WordPress theme uses the **exact same CSS classes** as the static site, so visual parity is achieved by using the correct HTML structure.

---

### 1. Navigation

**Theme file:** `header.php`
**Status:** DONE in theme

| Element | Static Site | WordPress |
|---------|-------------|-----------|
| Logo | `images/logo.png` | `assets/images/logo.png` via `get_template_directory_uri()` |
| Logo text | `Lillestrøm` / `Osteopati` | Hardcoded in template |
| Menu items | Hardcoded `<a>` links | `wp_nav_menu()` with `LO_Nav_Walker` |
| Mobile toggle | 3-span hamburger | Same markup in `header.php` |
| CTA button | Last item with `.nav-cta` | Walker adds `.nav-cta` to last menu item |

**Manual steps:**
1. After theme activation, go to **Appearance > Menus**
2. Verify "Hovedmeny" exists with all 11 items (auto-created on activation)
3. Ensure the menu is assigned to "Hovedmeny" location
4. The last item ("Bestill time") must be the final item to get the `.nav-cta` class

---

### 2. Hero

**Theme file:** `template-parts/section-hero.php`
**Status:** DONE in theme

| Element | Source | Editable via |
|---------|--------|-------------|
| Subtitle | "Velkommen til" | Customizer: `lo_hero_subtitle` |
| Title | "Lillestrøm Osteopati" | Customizer: `lo_hero_title` |
| Description | Clinic description text | Customizer: `lo_hero_description` |
| Primary button | "Bestill time" | Customizer: `lo_hero_btn_primary` |
| Secondary button | "Les mer om osteopati" | Customizer: `lo_hero_btn_secondary` |
| Badge icons | `fa-user-md`, `fa-clock`, `fa-file-medical` | Hardcoded in template |
| Scroll arrow | `fa-chevron-down` | Hardcoded in template |
| Background | CSS gradient + grain SVG overlay | `style.css` (`.hero`, `.hero::before`, `.hero-overlay`) |

**Manual steps:**
1. Go to **Appearance > Customize > Lillestrøm Osteopati > Hero**
2. Verify all text fields match the static site defaults
3. The gradient background and grain overlay are pure CSS — no action needed

---

### 3. Om oss (About)

**Theme file:** `template-parts/section-about.php`
**Status:** DONE in theme

| Element | Source | Editable via |
|---------|--------|-------------|
| Section label | "Om oss" | Hardcoded (`esc_html_e`) |
| Title | "Din helse i trygge hender" | Hardcoded |
| Clinic photo | `klinikk.png` | Theme asset (`assets/images/klinikk.png`) |
| Lead text | Intro paragraph | Customizer: `lo_about_lead` |
| Paragraph 1 | Authorization text | Customizer: `lo_about_text1` |
| Paragraph 2 | Capacity text | Customizer: `lo_about_text2` |
| Stat 1 | "4-årig" / "Høyskoleutdanning" | Customizer: `lo_about_stat1_number`, `lo_about_stat1_label` |
| Stat 2 | "45–60" / "Min. per konsultasjon" | Customizer: `lo_about_stat2_number`, `lo_about_stat2_label` |
| Stat 3 | "100%" / "Fokus på deg" | Customizer: `lo_about_stat3_number`, `lo_about_stat3_label` |

**Manual steps:**
1. Upload `klinikk.png` to `assets/images/` in the theme folder (via FTP)
2. Verify in Customizer under **Om oss** that text matches

---

### 4. Osteopati

**Theme file:** `template-parts/section-osteopati.php`
**Status:** DONE in theme

| Element | Icons | Editable via |
|---------|-------|-------------|
| Card 1: Parietal | `fas fa-bone` | Customizer: `lo_osteo_card1_title`, `lo_osteo_card1_text` |
| Card 2: Visceral | `fas fa-lungs` | Customizer: `lo_osteo_card2_title`, `lo_osteo_card2_text` |
| Card 3: Kranial | `fas fa-brain` | Customizer: `lo_osteo_card3_title`, `lo_osteo_card3_text` |
| Intro paragraphs | — | Customizer: `lo_osteo_intro1`, `lo_osteo_intro2` |
| "Hvem passer det for?" | — | Customizer: `lo_osteo_who_title`, `lo_osteo_who_text1`, `lo_osteo_who_text2` |

**Manual steps:**
1. Verify all text in **Customize > Lillestrøm Osteopati > Osteopati**
2. Icons are hardcoded in the template — they match the static site exactly

---

### 5. Behandlinger (Treatments)

**Theme file:** `template-parts/section-behandlinger.php`
**Status:** DONE in theme

All 12 treatment cards are **hardcoded** in the template PHP as an array. Each card has:
- `icon` — Font Awesome class (e.g., `fa-arrow-down`)
- `title` — Norwegian treatment name
- `description` — Short description

The subtitle is editable via Customizer: `lo_behandlinger_subtitle`.

**Manual steps:**
1. Verify the 12 cards render correctly
2. To add/remove/reorder treatments, edit `section-behandlinger.php` directly
3. Icons are output as `<i class="fas {icon} treatment-icon">` — ensure FA 6.5.1 is loaded

---

### 6. Prosess (Process)

**Theme file:** `template-parts/section-prosess.php`
**Status:** DONE in theme

| Step | Title | Editable via |
|------|-------|-------------|
| 1 | Samtale | Customizer: `lo_prosess_step1_title`, `lo_prosess_step1_text` |
| 2 | Undersøkelse | Customizer: `lo_prosess_step2_title`, `lo_prosess_step2_text` |
| 3 | Behandling | Customizer: `lo_prosess_step3_title`, `lo_prosess_step3_text` |
| 4 | Oppfølging | Customizer: `lo_prosess_step4_title`, `lo_prosess_step4_text` |

**Manual steps:**
1. Verify in Customizer under **Prosess**
2. Numbers (1–4) are generated by the loop — they render as `.process-number` circles
3. This section uses `.section-dark` background — white text on dark

---

### 7. Behandlere (Staff)

**Theme file:** `template-parts/section-behandlere.php`
**Status:** DONE in theme

Uses the `behandler` Custom Post Type. Each post has:
- **Title** — Practitioner name (WordPress post title)
- **Content** — Bio paragraphs (WordPress editor)
- **Featured image** — Staff photo (falls back to `Behandling-T-10.jpg`)
- **Meta: `_behandler_title`** — Professional title (e.g., "Osteopat D.O. MNOF & Fysioterapeut")
- **Meta: `_behandler_education`** — One entry per line
- **Meta: `_behandler_specialties`** — One entry per line

Icons used:
- `fas fa-graduation-cap` — Education heading
- `fas fa-stethoscope` — Specialties heading

**Manual steps:**
1. Go to **Behandlere** in WordPress admin
2. Verify Thomas Sewell post exists (auto-created on activation)
3. Upload `Behandling-T-10.jpg` as the **Featured Image** for his post
4. To add more practitioners, create new `behandler` posts with all meta fields filled in
5. Use **Page Attributes > Order** to control display order

---

### 8. Forsikring (Insurance)

**Theme file:** NOT YET CREATED
**Status:** NEEDS TEMPLATE PART

This section needs a new file: `template-parts/section-forsikring.php`

**Content to replicate from static site:**

| Element | Content | Icon |
|---------|---------|------|
| Section label | "Forsikring" | — |
| Title | "Forsikring og dekning" | — |
| Subtitle | Long text about insurance | Customizer: `lo_forsikring_subtitle` |
| 3-step process | Sjekk forsikring → Bestill time → Vi fakturerer | Numbered list (CSS counters) |
| Insurance companies | If/Vertikal Helse, Storebrand, Gjensidige, Tryg, DNB, SpareBank 1 | Customizer: `lo_forsikring_companies` |
| Note | "Har du et annet forsikringsselskap?" | `fas fa-info-circle` |

**CSS classes to use:** `.insurance-content`, `.insurance-steps`, `.insurance-list`, `.insurance-companies`, `.insurance-logos`, `.insurance-logo-item`, `.insurance-note`

---

### 9. Bedrift (Corporate)

**Theme file:** NOT YET CREATED
**Status:** NEEDS TEMPLATE PART

This section needs: `template-parts/section-bedrift.php`

**Content to replicate:**

| Element | Icons |
|---------|-------|
| 6 benefit badges | `fa-calendar-check`, `fa-smile`, `fa-piggy-bank`, `fa-chart-line`, `fa-users` |
| Description paragraphs | — |
| 3 service cards | `fa-building`, `fa-receipt`, `fa-percentage` |
| Statistics box | `fa-exclamation-triangle` |
| CTA | White primary button |

**CSS classes:** `.section-dark`, `.bedrift-benefits`, `.bedrift-benefit`, `.bedrift-services`, `.bedrift-card`, `.bedrift-card-icon`, `.bedrift-stats`, `.bedrift-stat-box`, `.bedrift-cta`

---

### 10. Priser (Pricing)

**Theme file:** NOT YET CREATED
**Status:** NEEDS TEMPLATE PART

This section needs: `template-parts/section-priser.php`

**Content to replicate:**

| Card | Title | Customizer Key |
|------|-------|----------------|
| Price 1 | Ny pasient / Førstekonsultasjon | `lo_price1_title`, `lo_price1_desc`, `lo_price1_amount` |
| Price 2 (featured) | Oppfølgende behandling | `lo_price2_title`, `lo_price2_desc`, `lo_price2_amount` |
| Price 3 | Barn (under 16 år) | `lo_price3_title`, `lo_price3_desc`, `lo_price3_amount` |

**CSS classes:** `.pricing-grid`, `.price-card`, `.price-card.featured`, `.price-badge`, `.price-description`, `.price-placeholder`, `.pricing-note`

> Note: Prices currently show "Pris kommer" — update via Customizer when real prices are decided.

---

### 11. Kontakt (Contact)

**Theme file:** NOT YET CREATED
**Status:** NEEDS TEMPLATE PART

This section needs: `template-parts/section-kontakt.php`

**Content to replicate:**

| Element | Icon | Customizer Key |
|---------|------|----------------|
| Address | `fas fa-map-marker-alt` | `lo_contact_address` |
| E-post | `fas fa-envelope` | `lo_contact_email` |
| Telefon | `fas fa-phone` | `lo_contact_phone` |
| Åpningstider | `fas fa-clock` | `lo_contact_hours` |
| Contact form | — | Contact Form 7 shortcode |

**CSS classes:** `.contact-grid`, `.contact-item`, `.contact-icon`, `.contact-form-wrap`

The contact form uses **Contact Form 7** instead of FormSubmit.co. The CF7 form is auto-created on theme activation. CSS overrides for CF7 are already in `style.css` (lines 1806–1912).

---

### 12. FAQ

**Theme file:** NOT YET CREATED
**Status:** NEEDS TEMPLATE PART

This section needs: `template-parts/section-faq.php`

Uses the `faq_item` Custom Post Type. Each FAQ post has:
- **Title** = Question
- **Content** = Answer
- **menu_order** = Display order

| Element | Icon |
|---------|------|
| Accordion toggle | `fas fa-chevron-down` |

**CSS classes:** `.faq-list`, `.faq-item`, `.faq-question`, `.faq-icon`, `.faq-answer`

The 8 initial FAQ posts are auto-created on theme activation. The accordion behavior requires the JavaScript from `script.js`.

---

### 13. Timebestilling (CTA)

**Theme file:** NOT YET CREATED
**Status:** NEEDS TEMPLATE PART

This section needs: `template-parts/section-cta.php`

| Element | Customizer Key |
|---------|----------------|
| Title | `lo_cta_title` |
| Description | `lo_cta_text` |
| Primary button (white) | Links to `tel:` with `lo_cta_phone` |
| Secondary button | Links to `#kontakt` |
| Note | `fas fa-shield-alt` — "Autorisert helsepersonell" |

**CSS classes:** `.section-cta`, `.cta-content`, `.cta-buttons`, `.cta-note`

---

### 14. Footer

**Theme file:** `footer.php`
**Status:** DONE in theme

| Element | Source |
|---------|--------|
| Logo | `assets/images/logo.png` |
| Tagline | Customizer: `lo_footer_tagline` |
| Navigation links | Hardcoded anchor links |
| Contact info | Customizer: `lo_contact_address`, `lo_contact_email` |
| Copyright year | `date('Y')` — auto-updates |
| Norsk Osteopatforbund link | Hardcoded |

---

## Contact Form Setup

The static site uses **FormSubmit.co**. The WordPress theme replaces this with **Contact Form 7**.

### Installation

1. Install and activate the **Contact Form 7** plugin
2. The theme auto-creates a form named "Kontaktskjema" on activation
3. The form ID is stored as theme mod `lo_cf7_form_id`

### Form Fields (matching static site)

| Field | Type | Required | Placeholder |
|-------|------|----------|-------------|
| Navn | text | Yes | "Ditt fulle navn" |
| E-post | email | Yes | "din@epost.no" |
| Telefon | tel | No | "Valgfritt" |
| Melding | textarea | Yes | "Beskriv kort hva du ønsker hjelp med..." |

### CF7 CSS Parity

The theme `style.css` already includes full CF7 style overrides (`.wpcf7` rules) that match the static site's form styling exactly, including:
- Input/textarea styling with focus states
- Submit button as `.btn .btn-primary .btn-submit`
- Validation error styling
- Response output styling

### Admin Bar Offset

The CSS includes a WordPress admin bar offset for the fixed navbar:

```css
body.admin-bar .navbar { top: 32px; }
@media (max-width: 782px) { body.admin-bar .navbar { top: 46px; } }
```

---

## Asset Checklist

### Images to Upload (FTP to theme folder)

| File | Destination | Used In |
|------|-------------|---------|
| `logo.png` | `assets/images/logo.png` | Navbar, Footer |
| `klinikk.png` | `assets/images/klinikk.png` | Om oss section |
| `Behandling-T-10.jpg` | `assets/images/Behandling-T-10.jpg` | Behandlere fallback |

Additional photos can be uploaded to WordPress Media Library and set as Featured Images on `behandler` posts.

### External Dependencies (CDN — no action needed)

| Asset | URL | Enqueued In |
|-------|-----|-------------|
| Google Fonts (Inter + Playfair Display) | `fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&family=Playfair+Display:wght@400;500;600;700&display=swap` | `functions.php` |
| Font Awesome 6.5.1 | `cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css` | `functions.php` |

### JavaScript

The `script.js` file must be placed at `assets/js/script.js` inside the theme folder. It is enqueued in `functions.php` as `lo-theme-script` with jQuery dependency.

**Features provided by script.js:**
- Navbar scroll effect (`.scrolled` class after 60px)
- Mobile menu toggle (`.open` class)
- Smooth scrolling for anchor links
- Scroll reveal animations (IntersectionObserver)
- FAQ accordion (one open at a time)
- Active nav link highlighting

---

## Visual Consistency Rules

To ensure every page/section looks identical to the static site:

### 1. CSS Variables Must Not Change

All visual identity is driven by these CSS custom properties in `style.css`:

```css
--color-primary:       #2A7D6E;   /* Teal green */
--color-primary-dark:  #1E5C51;
--color-primary-light: #3A9D8C;
--color-primary-muted: #E8F5F1;
--color-accent:        #C6975B;   /* Warm gold */
--color-accent-light:  #DDB87A;
--color-dark:          #1A2332;
--color-text:          #3A4553;
--font-heading:        'Playfair Display', Georgia, serif;
--font-body:           'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
```

### 2. Class Names Must Match Exactly

The CSS targets specific class names. All template parts must use the exact same class structure as `index.html`. Key patterns:

- Sections: `.section .section-light`, `.section .section-accent`, `.section .section-dark`
- Headers: `.section-header` > `.section-label` + `.section-title` + `.section-subtitle`
- Grids: `.osteo-grid`, `.treatments-grid`, `.process-grid`, `.pricing-grid`, `.contact-grid`, `.staff-grid`
- Cards: `.osteo-card`, `.treatment-card`, `.price-card`, `.bedrift-card`, `.staff-card`

### 3. Icon Format

All icons must use the pattern:

```html
<i class="fas fa-{icon-name}"></i>
```

Some icons are wrapped in styled containers:

```html
<!-- Osteopati cards -->
<div class="osteo-card-icon"><i class="fas fa-bone"></i></div>

<!-- Treatment cards -->
<i class="fas fa-arrow-down treatment-icon"></i>

<!-- Contact items -->
<div class="contact-icon"><i class="fas fa-envelope"></i></div>

<!-- Bedrift cards -->
<div class="bedrift-card-icon"><i class="fas fa-building"></i></div>
```

### 4. Section Background Pattern

| Background | CSS Class | Used By |
|------------|-----------|---------|
| White | `.section-light` | Om oss, Behandlinger, Behandlere, Priser |
| Light green | `.section-accent` | Osteopati, Kontakt |
| Dark navy | `.section-dark` | Prosess, Bedrift |
| Gradient teal | `.hero` | Hero (special) |
| Gradient primary | `.section-cta` | Timebestilling/CTA |

### 5. No WordPress Theme Conflicts

- Do NOT install additional CSS-heavy plugins (Elementor, Divi, etc.)
- Do NOT enable a child theme unless extending carefully
- The `wp_head()` and `wp_footer()` hooks are already in header/footer templates
- WordPress admin bar offset is already handled in CSS

---

## Post-Deployment Verification

After deploying the theme, verify each section:

- [ ] **Navigation** — Logo loads, all menu items scroll to correct sections, mobile hamburger works
- [ ] **Hero** — Gradient background renders, badges with icons display, buttons link correctly
- [ ] **Om oss** — Clinic photo loads, stats display, text is correct
- [ ] **Osteopati** — 3 cards with bone/lungs/brain icons, intro text, "hvem passer det for" subsection
- [ ] **Behandlinger** — 12 treatment cards with correct icons in a 4-column grid (2-col tablet, 1-col mobile)
- [ ] **Prosess** — 4 numbered steps on dark background
- [ ] **Behandlere** — Thomas Sewell card with photo, bio, education list, specialties list
- [ ] **Forsikring** — 3-step process, 6 insurance company boxes, info note with icon
- [ ] **Bedrift** — Benefit badges, 3 service cards, statistics box, CTA
- [ ] **Priser** — 3 price cards (middle one featured), pricing notes
- [ ] **Kontakt** — Contact info with icons, CF7 form styled correctly
- [ ] **FAQ** — 8 questions with accordion expand/collapse
- [ ] **Timebestilling** — CTA with white buttons on green gradient
- [ ] **Footer** — Logo, links, contact info, copyright
- [ ] **Mobile** — Test at 768px and 480px breakpoints
- [ ] **Scroll animations** — Elements fade in on scroll (IntersectionObserver)
- [ ] **Font Awesome** — All icons load (check browser network tab for FA CSS)
- [ ] **Google Fonts** — Inter and Playfair Display load correctly

---

## Remaining Work (Theme Gaps)

The following template parts need to be created to complete the WordPress theme:

| Priority | File | Section | Complexity |
|----------|------|---------|------------|
| 1 | `template-parts/section-forsikring.php` | Forsikring | Medium — uses Customizer values, CSS counters |
| 2 | `template-parts/section-bedrift.php` | Bedrift | Medium — multiple sub-components, dark section |
| 3 | `template-parts/section-priser.php` | Priser | Low — 3 cards from Customizer values |
| 4 | `template-parts/section-kontakt.php` | Kontakt | Medium — contact info + CF7 shortcode |
| 5 | `template-parts/section-faq.php` | FAQ | Low — WP_Query for `faq_item` CPT + accordion |
| 6 | `template-parts/section-cta.php` | Timebestilling | Low — simple CTA from Customizer values |
| 7 | `template-parts/section-takk.php` | Thank you | Low — hidden section shown after form submit |
| 8 | `front-page.php` | Page template | Required — assembles all template parts in order |

Additionally:
- [ ] Create `assets/js/script.js` in theme (copy from static site, remove FormSubmit-specific code)
- [ ] Create `assets/images/` directory structure in theme
- [ ] Add Customizer settings for Bedrift section text (not yet in `customizer.php`)
- [ ] Test CF7 form submission and email delivery
- [ ] Replace placeholder prices, phone number, and address with real data
