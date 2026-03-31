# Deployment Guide — Lillestrøm Osteopati

How to remove the existing WordPress site from Domeneshop and replace it with the new static site.

---

## Overview

| Step | Action | Time |
|------|--------|------|
| 1 | Back up the existing WordPress site | 10 min |
| 2 | Connect to Domeneshop via FTP/SFTP | 5 min |
| 3 | Remove WordPress files from the `www` folder | 5 min |
| 4 | Upload the new static site files | 5 min |
| 5 | Verify the site is live | 2 min |
| 6 | (Optional) Remove the MySQL database | 2 min |
| 7 | Activate FormSubmit contact form | 5 min |

---

## Step 1: Back Up the Existing WordPress Site

Before deleting anything, take a backup.

### 1a. Back up via WordPress (recommended)

1. Log in to **https://lillestrom-osteopati.no/wp-admin**
2. Go to **Plugins > Add New** and install **Duplicator**
3. Go to **Duplicator > Packages > Create New**
4. Download the generated `installer.php` and `archive.zip` files to your PC
5. Store them in a safe location (e.g., `D:\opt\backup\lillestrom-osteopati-wp-backup\`)

### 1b. Back up the database separately

1. Log in to **https://www.domeneshop.no**
2. Select the domain `lillestrom-osteopati.no`
3. Go to the **Webhotell** tab
4. Click **MySQL** > **View/change**
5. Click the **export icon** to download a ZIP file of your database
6. Store the ZIP alongside the Duplicator backup

---

## Step 2: Connect via FTP or SFTP

You need an FTP/SFTP client to manage files on the server.

### Connection details

| Setting | Value |
|---------|-------|
| **Protocol** | SFTP (recommended) or FTP with AUTH TLS |
| **Server** | `sftp.domeneshop.no` (SFTP) or `ftp.domeneshop.no` (FTP) |
| **Port** | 22 (SFTP) or 21 (FTP) |
| **Username** | Your webhotell username (usually the domain name without TLD, check control panel) |
| **Password** | Your webhotell password (set in Domeneshop control panel) |

### Finding your FTP username and password

1. Log in to **https://www.domeneshop.no**
2. Select domain `lillestrom-osteopati.no`
3. Go to the **Webhotell** tab
4. Your FTP username is shown there
5. If you don't know the password, you can reset it from the same page

### Recommended FTP clients

- **WinSCP** (Windows, free) — https://winscp.net — supports SFTP natively
- **Cyberduck** (Windows/Mac, free) — https://cyberduck.io
- **CoreFTP** (Windows, free) — https://www.coreftp.com

### Alternative: SSH terminal access

If you have **Web hosting Medium or larger**, you can also connect via SSH:

```powershell
ssh username@login.domeneshop.no
```

This gives you command-line access to manage files directly.

---

## Step 3: Remove WordPress Files

Once connected via FTP/SFTP:

1. Navigate to the **`www`** directory (this is the web root)
2. You will see WordPress files like:
   - `wp-admin/`
   - `wp-content/`
   - `wp-includes/`
   - `wp-config.php`
   - `index.php`
   - `.htaccess`
   - etc.
3. **Select ALL files and folders** inside `www/`
4. **Delete them** (or move them to a `_wordpress_backup/` folder outside `www/` if you want a server-side backup)

### If using SSH terminal instead:

```bash
# Connect
ssh username@login.domeneshop.no

# Navigate to web root
cd www

# Move everything to a backup folder (safe approach)
mkdir -p ../wordpress_backup
mv * ../wordpress_backup/
mv .htaccess ../wordpress_backup/

# Verify www is empty
ls -la
```

---

## Step 4: Upload the New Static Site

Upload these files from `D:\opt\src\Misc\LillestromOsteopati\` to the **`www`** directory:

```
www/
├── index.html
├── styles.css
├── script.js
└── images/
    ├── logo.png
    ├── klinikk.png
    ├── header_logo.gif
    ├── header_logo.webp
    ├── Behandling-T-10.jpg
    ├── Behandling-T-2.jpg
    ├── Behandling-Petter-4.jpg
    ├── Behandlingsrom-3.jpg
    ├── Gruppebilde-5.jpg
    └── (other images)
```

### Using WinSCP or Cyberduck:

1. In the left panel (local), navigate to `D:\opt\src\Misc\LillestromOsteopati\`
2. In the right panel (remote), navigate to `www/`
3. Select `index.html`, `styles.css`, `script.js`, and the `images/` folder
4. Drag them to the `www/` directory (or click Upload)
5. Wait for the transfer to complete

### Using SSH + SCP from PowerShell:

```powershell
# Upload all site files to the www directory
scp -r D:\opt\src\Misc\LillestromOsteopati\index.html username@scp.domeneshop.no:www/
scp -r D:\opt\src\Misc\LillestromOsteopati\styles.css username@scp.domeneshop.no:www/
scp -r D:\opt\src\Misc\LillestromOsteopati\script.js username@scp.domeneshop.no:www/
scp -r D:\opt\src\Misc\LillestromOsteopati\images username@scp.domeneshop.no:www/
```

**Do NOT upload** these files (they are development/documentation only):
- `README.md`
- `research.md`
- `DEPLOY.md`

---

## Step 5: Verify the Site is Live

1. Open **https://lillestrom-osteopati.no** in your browser
2. Hard refresh with **Ctrl+Shift+R** to clear any cached WordPress pages
3. Check that:
   - [x] The homepage loads with the new design
   - [x] Logo appears in the navbar
   - [x] All images load (clinic photo, treatment photos)
   - [x] Navigation links scroll to the correct sections
   - [x] Mobile menu works (test on phone or resize browser)
   - [x] The site works with both `www.` and without

### If you see the old WordPress site:

- Your browser may be caching. Try incognito/private window.
- DNS propagation is not needed (you're using the same domain/hosting).
- Check that `index.html` is in the `www/` root, not in a subfolder.

---

## Step 6: (Optional) Remove the MySQL Database

WordPress uses a MySQL database that is no longer needed. You can keep it (it costs nothing) or remove it:

1. Log in to **https://www.domeneshop.no**
2. Select domain `lillestrom-osteopati.no`
3. Go to **Webhotell** tab > **MySQL**
4. You can delete the database from here if desired

**Note:** Only do this AFTER confirming the new site works and you have a backup of the database (Step 1b).

---

## Step 7: Activate the Contact Form (FormSubmit)

The contact form uses [FormSubmit.co](https://formsubmit.co) — a free service that forwards form submissions as email.

1. Go to **https://lillestrom-osteopati.no**
2. Scroll to the **Kontakt** section
3. Fill in and **submit the contact form** with test data
4. FormSubmit will send a **confirmation email** to `post@lillestrom-osteopati.no`
5. Open that email and **click the confirmation link**
6. After confirming, all future form submissions will be delivered to `post@lillestrom-osteopati.no`

### Important notes about FormSubmit:

- The email address is visible in the HTML source code. After first confirmation, FormSubmit provides a **hashed URL** you can use instead for privacy. Check the confirmation email for details.
- FormSubmit includes honeypot spam protection (already configured in the form).
- The form redirects users to a "Takk" (Thank You) section after submission.

---

## Troubleshooting

### "403 Forbidden" error
- Check file permissions. Files should be readable (644), directories should be 755.
- Via SSH: `chmod -R 644 www/*.html www/*.css www/*.js && chmod 755 www/ www/images/`

### Images not loading
- Check that the `images/` folder was uploaded inside `www/`
- File names are case-sensitive on Linux servers. Ensure exact case matches.

### Site shows directory listing instead of the page
- Make sure the file is named `index.html` (not `Index.html` or `home.html`)

### Old WordPress pages still showing
- Clear browser cache (Ctrl+Shift+Delete)
- Check that no WordPress files remain in `www/`
- Check for `.htaccess` redirects left over from WordPress

---

## Future Updates

To update the site in the future:

1. Edit files locally in `D:\opt\src\Misc\LillestromOsteopati\`
2. Test with the local server: `npx http-server . -p 8080 -o`
3. Upload changed files via FTP/SFTP to `www/`

No build step, no deployment pipeline — just upload and it's live.

---

## Reference Links

- Domeneshop FAQ — Uploading files: https://domene.shop/faq?id=56
- Domeneshop FAQ — FTP login issues: https://domene.shop/faq?id=58
- Domeneshop FAQ — SSH access: https://domene.shop/faq?id=64
- Domeneshop FAQ — MySQL backup: https://domene.shop/faq?id=117
- Domeneshop FAQ — phpMyAdmin: https://domene.shop/faq?id=390
- FormSubmit documentation: https://formsubmit.co/documentation
