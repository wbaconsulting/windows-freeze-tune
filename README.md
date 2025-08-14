# WindowsFreezeTune (by WBA Consulting)

A tiny, reversible PowerShell toolkit that fixes common **random desktop freezes** by:
- Disabling **USB selective suspend** (stops flaky hubs/peripherals sleeping)
- Turning **PCIe ASPM** **off** (prevents link state power weirdness)
- Disabling **Hibernation** (also disables Fast Startup)
- (Optional) Removing **Intel XTU** service & driver packages that linger after uninstall
- Saving an **undo** backup and logging evidence (critical events + devices “not OK”)

> Works on Windows 10/11. No external downloads. Everything is **auditable** and **reversible**.

---

## TL;DR

**Run (as Admin):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\WindowsFreezeTune.ps1
