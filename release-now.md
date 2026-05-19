## Overview

**SignGuiPatcher v2.0** removes desktop watermarks on Windows evaluation, insider and test-signing builds —
Vista through Windows 11 Build 28000 — without modifying any system file.

Complete rewrite in pure MASM x64 (zero CRT). Adds full support for Windows 11 Build 28000+
where watermarks are rendered via `UxTheme!DrawTextWithGlow` (ordinal 126).

---

## What's New in v2.0

- **Rewritten in pure MASM x64** — no C++ runtime, no CRT, single self-contained EXE
- **DrawTextWithGlow hook** — intercepts UxTheme ordinal 126 (the renderer on Win11 Build 28000+)
- **BrandingLoadStringForEdition hook** — delay-IAT by name (works before winbrand.dll is loaded)
- **Delay-load INT scanner** — patches by name or ordinal directly from the PE Import Name Table
- **CLI mode** — `-apply` / `-restore` / `-status` for scripted deployment
- **Dark mode + Mica** — GUI adapts to Windows 11 system theme
- **Defense-in-depth** — five hooks cover every rendering path from Vista to Build 28000

---

## 📦 Archive Contents (`SignGuiPatcher.7z` — ${SIZE_7Z})

```
SignGuiPatcher.7z   (password: github.com)
└── SignGuiPatcher.exe    Patcher (MASM x64, no CRT, requireAdministrator)
```

---

## 🚀 Usage

Run `SignGuiPatcher.exe` as Administrator.

**GUI mode:** double-click → UAC prompt → click APPLY PATCH

**CLI mode:**
```
SignGuiPatcher.exe -apply      Apply watermark patch
SignGuiPatcher.exe -restore    Restore original state
SignGuiPatcher.exe -status     Check current state
```

Explorer restarts automatically. No logout required. Fully reversible.

---

## ✅ Tested On

- Windows 11 26H1 **10.0.28000** — all watermarks suppressed
- Windows 10 22H2 — Test Mode + build string suppressed
- Windows 7 — evaluation watermark suppressed

---

## ⚙️ Technical

- **COM CLSID hijack** — `ExpIorerFrame.dll` (capital I, visually identical to lowercase l)
  replaces `ExplorerFrame.dll` via one registry character change
- **Five IAT hooks** — LoadStringW, ExtTextOutW, DrawTextW, BrandingLoadStringForEdition, DrawTextWithGlow
- **TrustedInstaller impersonation** — no driver, no service install, no kernel modification
- Pure **MASM x64**, zero CRT — kernel32 + advapi32 + shell32 + user32 only

---

## ⚠️ Responsible Use

For authorized use only on systems you own or administer — evaluation machines,
insider preview installs, test-signing development environments.
Not a license bypass or activation crack. All changes are fully reversible.
The author is not responsible for any damage.

---

## 📞 Contact

- **Email:** marek@wesolowski.eu.org
- **GitHub:** https://github.com/${REPO}

---

*Release: ${TAG} · ${DATE} · © WESMAR 2026*
