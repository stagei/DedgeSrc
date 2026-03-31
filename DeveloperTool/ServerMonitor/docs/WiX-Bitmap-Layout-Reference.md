# WiX v6 Bitmap Layout Reference

Pixel-precise reference for `WixUIBannerBmp` and `WixUIDialogBmp` used in `WixUI_InstallDir`.

---

## Coordinate System

| Property | Value |
|---|---|
| Dialog size | 370 × 270 dialog units (DU) |
| Bitmap area | Top 234 DU (bottom 36 DU reserved for buttons) |
| Banner bitmap size | **493 × 58 px** |
| Dialog bitmap size | **493 × 312 px** |
| Scale (width) | 1 DU ≈ 1.332 px (`493 / 370`) |
| Scale (height) | 1 DU ≈ 1.333 px (`312 / 234`) |

### Converting between DU and pixels

```
pixel_x = dialog_unit_x × (493 / 370)
pixel_y = dialog_unit_y × (312 / 234)
```

---

## WixUIDialogBmp (493 × 312 px)

Used on the **WelcomeDlg** and **ExitDlg** (finish) pages.

```
  0px                 163px 180px                              473px 493px
  ├──── Left Panel ────┤     ├────── WiX Text Zone ──────────────┤
  │                    │     │                                    │
  │  Your branding     │ gap │  Title (WiX renders text here)    │  27px
  │  - icon            │     │  Font: Tahoma 12pt bold           │
  │  - product name    │     │  "Welcome to the [ProductName]    │
  │  - version         │     │   Setup Wizard"                   │ 107px
  │                    │     ├────────────────────────────────────┤
  │  Safe to paint     │     │  Description (WiX renders here)   │
  │  anything here.    │     │  Font: Tahoma 8pt regular         │
  │  WiX never         │     │  "The Setup Wizard will install   │
  │  touches this      │     │   [ProductName] on your..."       │
  │  area.             │     │                                   │ 187px
  │                    │     ├────────────────────────────────────┤
  │                    │     │                                    │
  │                    │     │  Dead zone (empty, safe to paint)  │
  │                    │     │                                    │
  │                    │     │                                    │ 312px
  └────────────────────┘     └────────────────────────────────────┘
```

### Zone Map (pixel coordinates)

| Zone | X range | Y range | Size (px) | Usage |
|---|---|---|---|---|
| **Left panel** | 0 – 163 | 0 – 312 | 163 × 312 | Safe for branding. WiX never renders here. |
| **Gap** | 164 – 179 | 0 – 312 | 16 × 312 | Separator / margin. Avoid content. |
| **Title** | 180 – 473 | 27 – 107 | 293 × 80 | WiX renders title text. Do NOT paint here. |
| **Description** | 180 – 473 | 107 – 187 | 293 × 80 | WiX renders description. Do NOT paint here. |
| **Dead zone** | 180 – 473 | 187 – 312 | 293 × 125 | Below WiX text. Safe for copyright, version, etc. |
| **Top margin** | 180 – 473 | 0 – 27 | 293 × 27 | Above title. Small, mostly empty. |

### WiX text rendering notes

- Text controls have `Transparent="yes"` — they render directly on the bitmap.
- Font color uses **system default** (`0x80000000`). On most systems this is black, but on
  dark-mode or high-contrast systems it may be white/invisible on a white background.
- There is **no way to change the font color** of the built-in WelcomeDlg text in `WixUI_InstallDir`.
- If you need guaranteed-visible text: paint it on the bitmap and accept that WiX's invisible
  text may render on top (won't be visible, so no harm).

### Safe painting strategy

**Option A — Trust WiX text (recommended for light-mode systems)**
- Paint branding only in the left panel (0–163px).
- Keep the right panel (164–493px) plain white.
- WiX renders its own title + description in black.

**Option B — Paint your own text (guaranteed visible everywhere)**
- Paint branding in the left panel (0–163px).
- Paint your own title at ~(184, 30) and description at ~(184, 110) in dark color.
- WiX's system-color text will also render but typically matches or is invisible.
- Risk: double text if WiX text is also visible.

**Option C — Hybrid**
- Left panel: branding.
- Dead zone (180–473, 187–312): copyright, version, additional info.
- Title/description zones: leave white for WiX.

---

## WixUIBannerBmp (493 × 58 px)

Used on **all inner dialogs** (LicenseAgreementDlg, InstallDirDlg, VerifyReadyDlg, ProgressDlg, etc.).

```
  0px                                              440px  493px
  ├──────── WiX Title + Description ─────────────────┤ icon ┤
  │                                                   │      │
  │  Title: X=15 DU → ~20px, Y=15 DU → ~10px         │ Safe │
  │  Description: X=25 DU → ~33px, Y=35 DU → ~24px   │ for  │  58px
  │                                                   │ logo │
  └───────────────────────────────────────────────────┘──────┘
```

### Zone Map (pixel coordinates)

| Zone | X range | Y range | Size (px) | Usage |
|---|---|---|---|---|
| **Title** | 20 – 413 | 6 – 22 | 393 × 16 | WiX renders bold title. Do NOT paint here. |
| **Description** | 33 – 413 | 22 – 50 | 380 × 28 | WiX renders description. Do NOT paint here. |
| **Icon area** | 413 – 493 | 0 – 58 | 80 × 58 | Safe for small logo/icon (right-aligned). |
| **Bottom margin** | 0 – 493 | 50 – 58 | 493 × 8 | Below text, narrow. |

### Recommended banner layout

- **Background**: white.
- **Icon**: FK circle icon, 40×40 px, positioned at (445, 9) — right-aligned with padding.
- **Left area**: leave white for WiX to render each dialog's title and description.

---

## Standard Dialog Dimensions

All WiX built-in dialogs use these consistent positions (in dialog units):

| Control | X (DU) | Y (DU) | W (DU) | H (DU) | X (px) | Y (px) |
|---|---|---|---|---|---|---|
| Banner bitmap | 0 | 0 | 370 | 44 | 0 | 0 |
| Banner separator line | 0 | 44 | 370 | 0 | 0 | 59 |
| Inner dialog title | 15 | 6 | 300 | 15 | 20 | 8 |
| Inner dialog description | 25 | 23 | 280 | 15 | 33 | 31 |
| Bottom separator line | 0 | 234 | 370 | 0 | 0 | 312 |
| Back button | 180 | 243 | 56 | 17 | 240 | 324 |
| Next button | 236 | 243 | 56 | 17 | 314 | 324 |
| Cancel button | 304 | 243 | 56 | 17 | 405 | 324 |

---

## PowerShell Bitmap Generation Template

```powershell
Add-Type -AssemblyName System.Drawing

function Get-IconBitmap([string]$path, [int]$size) {
    $ico = New-Object System.Drawing.Icon($path, $size, $size)
    $bmp = $ico.ToBitmap()
    $ico.Dispose()
    $result = New-Object System.Drawing.Bitmap($size, $size)
    $gr = [System.Drawing.Graphics]::FromImage($result)
    $gr.InterpolationMode = 'HighQualityBicubic'
    $gr.DrawImage($bmp, 0, 0, $size, $size)
    $gr.Dispose(); $bmp.Dispose()
    return $result
}

# IMPORTANT: Use DrawImage with explicit W,H to control icon size.
# DrawIcon renders at the icon's NATIVE resolution (often 256x256).

# Banner: 493x58, white, 40px icon right-aligned
$iconSmall = Get-IconBitmap "app.ico" 40
$banner = New-Object System.Drawing.Bitmap(493, 58)
$g = [System.Drawing.Graphics]::FromImage($banner)
$g.Clear([System.Drawing.Color]::White)
$g.DrawImage($iconSmall, (493-40-10), 9, 40, 40)  # Explicit 40x40
$g.Dispose(); $banner.Save("WixBanner.bmp", [System.Drawing.Imaging.ImageFormat]::Bmp)

# Dialog: 493x312, left panel + white right
$iconMed = Get-IconBitmap "app.ico" 48
$dialog = New-Object System.Drawing.Bitmap(493, 312)
$g = [System.Drawing.Graphics]::FromImage($dialog)
$g.Clear([System.Drawing.Color]::White)
# Left panel: 0 to 163px
$g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(0,98,65))), 0, 0, 163, 312)
$g.DrawImage($iconMed, 57, 30, 48, 48)  # Centred in 163px panel, explicit 48x48
# ... add text to left panel only ...
$g.Dispose(); $dialog.Save("WixDialog.bmp", [System.Drawing.Imaging.ImageFormat]::Bmp)
```

### Critical rule: DrawIcon vs DrawImage

| Method | Behaviour | Use? |
|---|---|---|
| `DrawIcon($ico, x, y)` | Draws at icon's **native** size (e.g. 256×256) | **NO** |
| `DrawImage($bmp, x, y, w, h)` | Draws at **specified** w×h | **YES** |

Always convert `.ico` → `Bitmap` via `.ToBitmap()`, then use `DrawImage` with explicit dimensions.
