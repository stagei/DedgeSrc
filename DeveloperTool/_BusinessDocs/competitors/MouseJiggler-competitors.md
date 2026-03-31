# MouseJiggler — Competitor Analysis

**Product:** MouseJiggler — Session keep-alive tray utility with Bluetooth proximity detection
**Category:** Session Keep-Alive & Anti-Idle Utilities
**Date:** 2026-03-31

## Competitor Summary

| Name | URL | Pricing |
|------|-----|---------|
| Mouse Jiggler (Arkane Systems) | https://github.com/arkane-systems/mousejiggler | Free / Open Source (MS-PL) |
| Move Mouse | https://apps.microsoft.com/detail/move-mouse | Free |
| Caffeine | https://www.zhornsoftware.co.uk/caffeine | Free |
| PowerToys Awake | https://github.com/microsoft/PowerToys | Free / Open Source (MIT) |
| Don't Sleep | https://www.softwareok.com/?seession=Softwareok/DontSleep | Free |

## Detailed Competitor Profiles

### Mouse Jiggler (Arkane Systems)
Mouse Jiggler is the most well-known open-source mouse jiggler (1.3k GitHub stars). It runs in the system tray and simulates mouse movement to prevent idle detection. Available via Winget, Chocolatey, or direct download. Version 3.0.0 supports Windows 10/11 (64-bit only). Released under the MS-PL license. **Key difference from Dedge MouseJiggler:** Arkane's Mouse Jiggler is explicitly detectable by monitoring software (noted in their documentation). Dedge MouseJiggler adds Bluetooth proximity detection, automatically activating/deactivating based on whether your phone or other Bluetooth device is nearby — a feature no competitor offers.

### Move Mouse
Move Mouse is a feature-rich freeware mouse mover available on the Microsoft Store (v4.19.3). It supports customizable movement scheduling, click simulation, keyboard typing simulation, blackout scheduling, PowerShell script integration, dual monitor support, stealth mode, and activity logging. **Key difference:** Move Mouse is more feature-rich in mouse movement customization but lacks Bluetooth proximity detection. Dedge MouseJiggler's proximity feature provides automatic hands-free activation based on physical presence.

### Caffeine
Caffeine is a minimalist keep-alive tool that simulates a keypress (F15) every 59 seconds to prevent the system from going idle. It sits in the system tray with a simple on/off toggle. Very lightweight with virtually no configuration. **Key difference:** Caffeine is extremely simple (single keypress simulation only). Dedge MouseJiggler provides actual mouse movement simulation plus Bluetooth proximity detection for automatic activation based on user presence.

### PowerToys Awake
Microsoft PowerToys includes an Awake utility that keeps the PC awake without requiring constant mouse movement. It integrates with the Windows power plan and offers timed or indefinite keep-awake modes. Part of the official Microsoft PowerToys suite. **Key difference:** PowerToys Awake prevents sleep but doesn't simulate user input — it won't prevent screen lock policies enforced by Group Policy. Dedge MouseJiggler simulates actual mouse input and adds Bluetooth proximity for automatic activation.

### Don't Sleep
Don't Sleep is a portable freeware tool that prevents shutdown, standby, hibernate, and screen saver activation. It offers timer-based rules, system tray operation, and blocklist/allowlist for when to be active. **Key difference:** Don't Sleep focuses on preventing system power state changes rather than simulating user activity. It won't bypass screen lock policies. Dedge MouseJiggler simulates genuine mouse input and provides Bluetooth proximity detection.
