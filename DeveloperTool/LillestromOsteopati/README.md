# Lillestrøm Osteopati

Static website for [Lillestrøm Osteopati](https://lillestrom-osteopati.no/) — a healthcare/osteopathy clinic in Lillestrøm, Norway.

## Project Structure

```
LillestromOsteopati/
├── index.html      # Single-page site with all sections
├── styles.css      # Full responsive stylesheet
├── script.js       # Navigation, mobile menu, scroll animations
├── research.md     # Background research and content reference
└── README.md       # This file
```

## Sections

| Section         | Description                                        |
|-----------------|----------------------------------------------------|
| Hero            | Welcome banner with CTA buttons and trust badges   |
| Om oss          | About the clinic, credentials, stats               |
| Osteopati       | Three branches: parietal, visceral, cranial         |
| Behandlinger    | 8 treatment categories (back, head, sports, etc.)  |
| Prosess         | 4-step first-visit walkthrough                     |
| Forsikring      | Insurance info and partner companies               |
| Priser          | Pricing cards (placeholder — needs real prices)    |
| Kontakt         | Address, phone, email, hours, map placeholder      |
| Timebestilling  | Call-to-action for booking                         |

## Deployment to Domeneshop

The site is hosted on [Domeneshop](https://www.domeneshop.no/). To deploy:

1. **Log in** to Domeneshop control panel
2. Navigate to **Webhotell** (web hosting) for `lillestrom-osteopati.no`
3. **Upload files** via FTP or the file manager:
   - `index.html`
   - `styles.css`
   - `script.js`
   - Any images added later
4. Place all files in the **public_html** (or root web directory)
5. The WordPress installation can be backed up and removed once satisfied

### FTP Details (from Domeneshop)
- Host: typically `ftp.lillestrom-osteopati.no` or provided in panel
- Use SFTP if available
- Upload to the web root directory

## Placeholders to Fill In

Before going live, these items need real data:

- [ ] **Prices** — Add actual consultation prices
- [ ] **Phone number** — Replace placeholder in contact and CTA sections
- [ ] **Exact address** — Full street address in Lillestrøm
- [ ] **Clinic photo** — Replace the image placeholder in "Om oss"
- [ ] **Google Maps embed** — Add map iframe in contact section
- [ ] **Opening hours** — Verify and update
- [ ] **Booking system** — Link to online booking if available (e.g., Vello, Helseboka)
- [ ] **Insurance companies** — Verify the list of partner insurers
- [ ] **Thomas Sewell bio** — Add practitioner info when available
- [ ] **Favicon** — Add a favicon.ico

## Technology

- Pure HTML5, CSS3, JavaScript (no frameworks, no build step)
- Google Fonts: Inter + Playfair Display
- Font Awesome 6.5 icons
- Fully responsive (mobile, tablet, desktop)
- Scroll-reveal animations via IntersectionObserver
- No cookies, no tracking, no external dependencies beyond fonts/icons
