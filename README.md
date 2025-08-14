![CI](https://github.com/wbaconsulting/windows-freeze-tune/actions/workflows/ci.yml/badge.svg)
![Latest release](https://img.shields.io/github/v/release/wbaconsulting/windows-freeze-tune)
![Latest tag](https://img.shields.io/github/v/tag/wbaconsulting/windows-freeze-tune)


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
```

**Undo later:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\WindowsFreezeTune.ps1 -Undo
```

- Logs → `%Public%\WindowsFreezeTune-Logs\`  
- Backup → `%ProgramData%\WindowsFreezeTune\backup.json`

---

## What it changes (and why)

- **USB selective suspend → Disabled (AC/DC)**  
  USB hubs, KVMs, DACs, VR sensors and some keyboards/mice misbehave when Windows tries to suspend ports.

- **PCIe ASPM → Off (AC/DC)**  
  Prevents link power state transitions that can hang some GPUs, NVMe controllers, capture cards, etc.

- **Hibernation → Off**  
  Removes Fast Startup side-effects and frees the `hiberfil.sys` file. Re-enable via `-Undo`.

- **Intel XTU remnants → Attempted removal**  
  Cleans the `XTU3SERVICE` Windows service and `pnputil` driver packages named `xtu*.inf`.

Everything is written to a small JSON backup so you can revert.

---

## Requirements

- Windows 10/11, **Administrator** PowerShell  
- PowerShell 5.1+ (Windows PowerShell is fine)  
- Built-ins: `powercfg`, `pnputil`, `sc`, `Get-PnpDevice`, `Get-WinEvent`

---

## Safety & Undo

- The script **backs up** your current power plan values (USB suspend, PCIe ASPM) and **hibernation state**.
- Use `-Undo` to restore those exact values.
- If something fails, the script continues safely and prints what it managed to change.

---

## Why trust this?

- Single-file script, no network calls, no obfuscation.
- You can read it in 2 minutes. It’s all in `scripts/WindowsFreezeTune.ps1`.
- We provide a testable **repro** path: check Event Viewer (Critical events) and Device Manager, before/after.

---

## Inspiration & related tools

Sophia Script (SophiApp), privacy.sexy, O&O ShutUp10++, WinUtil, Harden-Windows-Security  
We focused this repo on **stability** (freeze fixes) and **reversibility**, not broad “debloat”.

---

## Roadmap

- Optional “Gaming preset” (latency-friendly power settings)  
- Packaging for **PowerShell Gallery** / **winget**  
- Telemetry-free usage stats (opt-in)

---

## License

MIT — see [LICENSE](./LICENSE).

© Watertown Business Advisory, LLC — https://wbaconsulting.org
