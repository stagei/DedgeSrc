# Deployment Guide — Lillestrøm Osteopati WordPress Theme

Deploy the custom WordPress theme to the existing WordPress installation on one.com.

---

## Prerequisites

- WordPress is already installed at `lillestrom-osteopati.no`
- You have wp-admin access (`lillestrom-osteopati.no/wp-admin`)
- The existing WordPress site can remain as-is — this theme replaces the front-end only

---

## Quick Deployment (5 minutes)

### Step 1: Create the theme ZIP

Run the packaging script from PowerShell:

```powershell
pwsh.exe -File "D:\opt\src\Misc\LillestromOsteopatiWordPress\deploy.ps1"
```

This creates `lillestrom-osteopati-v2.zip` in the same folder.

### Step 2: Install Contact Form 7

1. Log in to **https://lillestrom-osteopati.no/wp-admin**
2. Go to **Plugins > Add New**
3. Search for **Contact Form 7**
4. Click **Install Now**, then **Activate**

### Step 3: Upload and activate the theme

1. Go to **Appearance > Themes > Add New > Upload Theme**
2. Choose the `lillestrom-osteopati-v2.zip` file
3. Click **Install Now**
4. Click **Activate**

### Step 4: Done

The theme activation automatically:
- Creates a "Hjem" page and sets it as the front page
- Creates the navigation menu with all section links
- Creates the first staff member (Thomas Sewell) with bio and credentials
- Creates all 8 FAQ entries
- Creates the Contact Form 7 form (if the plugin is active)

Visit **https://lillestrom-osteopati.no** to see the site.

---

## Editing Content

Your friend can edit all content through the WordPress admin without touching code.

### Edit text and images (live preview)

1. Go to **Appearance > Customize**
2. Open the **Lillestrøm Osteopati** panel
3. Each section has its own sub-panel (Hero, Om oss, Priser, etc.)
4. Edit text, click **Publish** — changes are live immediately

### Add/edit staff members

1. Go to **Behandlere** in the wp-admin sidebar
2. Click **Add New** or edit an existing entry
3. Fill in:
   - **Title** = practitioner name
   - **Content** = bio text (the editor, write paragraphs)
   - **Featured Image** = photo (right sidebar)
   - **Behandler-detaljer** box = professional title, education (one per line), specialties (one per line)
4. Set **Order** under Page Attributes to control display order (lower = first)
5. Click **Publish**

### Add/edit FAQ items

1. Go to **FAQ** in the wp-admin sidebar
2. Click **Add New** or edit an existing entry
3. **Title** = the question
4. **Content** = the answer
5. Set **Order** under Page Attributes for display order
6. Click **Publish**

### Edit the contact form

1. Go to **Contact > Contact Forms**
2. Edit "Kontaktskjema"
3. Modify fields, email recipient, or messages
4. Click **Save**

### Edit navigation menu

1. Go to **Appearance > Menus**
2. Edit the "Hovedmeny" menu
3. Add/remove/reorder items
4. Click **Save Menu**

---

## What's Editable Where

| Content | Where to edit |
|---------|--------------|
| Hero text, buttons | Appearance > Customize > Hero |
| About section | Appearance > Customize > Om oss |
| Osteopati section | Appearance > Customize > Osteopati |
| Treatment cards subtitle | Appearance > Customize > Behandlinger |
| Process steps (1-4) | Appearance > Customize > Prosess |
| Insurance info | Appearance > Customize > Forsikring |
| Prices | Appearance > Customize > Priser |
| Contact info | Appearance > Customize > Kontakt |
| CTA / Bestill time | Appearance > Customize > Timebestilling |
| Footer tagline | Appearance > Customize > Footer |
| Staff / Behandlere | Behandlere (sidebar menu) |
| FAQ items | FAQ (sidebar menu) |
| Contact form | Contact > Contact Forms |
| Navigation menu | Appearance > Menus |

---

## Theme Structure

```
lillestrom-osteopati-v2/
├── style.css              # Theme stylesheet (all CSS)
├── functions.php          # Theme setup, enqueues, helpers
├── front-page.php         # Homepage template
├── header.php             # HTML head + navigation
├── footer.php             # Footer + closing tags
├── assets/
│   ├── js/script.js       # Navigation, scroll, FAQ accordion
│   └── images/            # All site images
├── inc/
│   ├── customizer.php     # WordPress Customizer settings
│   ├── post-types.php     # Custom Post Types (behandler, faq_item)
│   └── theme-setup.php    # Auto-setup on theme activation
└── template-parts/
    ├── section-hero.php
    ├── section-about.php
    ├── section-osteopati.php
    ├── section-behandlinger.php
    ├── section-prosess.php
    ├── section-behandlere.php
    ├── section-forsikring.php
    ├── section-bedrift.php
    ├── section-priser.php
    ├── section-kontakt.php
    ├── section-faq.php
    ├── section-timebestilling.php
    └── section-takk.php
```

---

## Plugin Dependencies

| Plugin | Required? | Purpose |
|--------|-----------|---------|
| Contact Form 7 | Recommended | Contact form with email delivery. Falls back to FormSubmit.co if not installed. |

No premium plugins required. No ACF, no page builders.

---

## Troubleshooting

### Site shows "Page not found" or blog posts instead of the homepage
- Go to **Settings > Reading**
- Set "Your homepage displays" to **A static page**
- Select "Hjem" as the Homepage
- Click **Save Changes**

### Contact form not showing
- Install and activate the **Contact Form 7** plugin
- Deactivate and reactivate the theme (this re-runs the setup to create the form)

### Images not loading
- Clear browser cache (Ctrl+Shift+R)
- Check that the theme is activated (Appearance > Themes)

### Staff member has no photo
- Edit the Behandler post
- Set a **Featured Image** in the right sidebar
- If no featured image is set, the theme uses a default placeholder

### Menu not showing correctly
- Go to **Appearance > Menus**
- Verify "Hovedmeny" is assigned to the "Hovedmeny" location
- If the menu is empty, deactivate/reactivate the theme to regenerate it
