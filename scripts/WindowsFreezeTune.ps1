param([switch]$Undo)

# ========= Safety: require Admin =========
$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
  Write-Error "Please run this script in an elevated (Administrator) PowerShell."
  exit 1
}

# ========= Paths =========
$BackupDir  = Join-Path $env:ProgramData 'WindowsFreezeTune'
$BackupJson = Join-Path $BackupDir 'backup.json'
$LogDir     = Join-Path $env:PUBLIC 'WindowsFreezeTune-Logs'
$DevicesCsv = Join-Path $LogDir 'Devices-Not-OK.csv'
$EventsTxt  = Join-Path $LogDir 'Critical-Events.txt'

# ========= Helpers =========
function Ensure-Dir($p){ if(-not(Test-Path $p)){ New-Item -ItemType Directory -Path $p -Force | Out-Null } }
function Header($t){ Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Normalize-Index($v){
  if (-not $v) { return $null }
  if ($v -is [int]) { return $v }
  if ($v -match '^0x[0-9a-fA-F]+$') { return [Convert]::ToInt32($v,16) }
  if ($v -match '^\d+$') { return [int]$v }
  return $null
}
function ActiveSchemeGuid(){
  try {
    $raw = powercfg /GETACTIVESCHEME 2>$null
    if ($raw) { return ($raw -replace '.*GUID:\s*([a-fA-F0-9-]+).*','$1') }
  } catch {}
  return $null
}
function QueryPower($scheme,$sub,$setting){
  $ac=''; $dc=''
  try {
    $out = powercfg /Q $scheme $sub $setting 2>$null
    if ($out) {
      $ac  = ($out | Select-String 'Current AC Power Setting Index:\s+(0x[0-9a-fA-F]+|\d+)').Matches.Value -replace '.*:\s+',''
      $dc  = ($out | Select-String 'Current DC Power Setting Index:\s+(0x[0-9a-fA-F]+|\d+)').Matches.Value -replace '.*:\s+',''
    }
  } catch {}
  @{AC=$ac; DC=$dc}
}
function SetPower($scheme,$sub,$setting,$ac,$dc){
  $acN = Normalize-Index $ac
  $dcN = Normalize-Index $dc
  if ($acN -ne $null) { try { powercfg /SETACVALUEINDEX $scheme $sub $setting $acN | Out-Null } catch {} }
  if ($dcN -ne $null) { try { powercfg /SETDCVALUEINDEX $scheme $sub $setting $dcN | Out-Null } catch {} }
  try { powercfg /S $scheme | Out-Null } catch {}
}

Ensure-Dir $BackupDir
Ensure-Dir $LogDir

# Known GUIDs
$SUB_USB  = '2a737441-1930-4402-8d77-b2bebba308a3' # USB settings
$USB_SEL  = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' # USB selective suspend
$SUB_PCI  = '501a4d13-42af-4429-9fd1-a8218c268e20' # PCIe
$ASPM     = 'ee12f906-d277-404b-b6da-e5fa1a576df5' # Link State Power Mgmt (ASPM)

$scheme = ActiveSchemeGuid
if (-not $scheme) {
  Write-Warning "Could not parse active power scheme GUID; using SCHEME_CURRENT alias."
  $scheme = 'SCHEME_CURRENT'
}

if ($Undo) {
  Header "Undoing changes (restore prior values)"
  if (!(Test-Path $BackupJson)) { Write-Warning "No backup found at $BackupJson"; exit 1 }
  $bak = Get-Content $BackupJson | ConvertFrom-Json

  if ($bak.Power) {
    SetPower ($bak.Power.Scheme   ?: $scheme) $SUB_USB $USB_SEL $bak.Power.USB.AC  $bak.Power.USB.DC
    SetPower ($bak.Power.Scheme   ?: $scheme) $SUB_PCI $ASPM    $bak.Power.PCIe.AC $bak.Power.PCIe.DC
    Write-Host "Restored USB selective suspend and PCIe ASPM."
  }

  if ($null -ne $bak.HibernateEnabled) {
    if ($bak.HibernateEnabled -eq 1) { powercfg -h on } else { powercfg -h off }
    Write-Host "Restored hibernation to $($bak.HibernateEnabled)."
  }
  Write-Host "Undo complete." -ForegroundColor Green
  exit 0
}

# ===== 1) Evidence =====
Header "Collecting evidence"
try {
  Get-WinEvent -FilterHashtable @{LogName='System'; Level=1; StartTime=(Get-Date).AddDays(-14)} |
    Format-Table TimeCreated, Id, ProviderName, Message -Wrap |
    Out-String | Set-Content -Encoding UTF8 $EventsTxt
  Write-Host "Saved critical events -> $EventsTxt"
} catch { Write-Warning "Could not export events: $_" }

try {
  $notOk = Get-PnpDevice | Where-Object Status -ne 'OK'
  $notOk | Export-Csv -NoTypeInformation -Encoding UTF8 $DevicesCsv
  Write-Host ("Devices not OK: {0} -> {1}" -f (@($notOk).Count), $DevicesCsv)
} catch { Write-Warning "Could not export device list: $_" }

# ===== 2) Backup current power + hibernate =====
Header "Backing up current power state"
$usbPrev  = QueryPower $scheme $SUB_USB $USB_SEL
$pciPrev  = QueryPower $scheme $SUB_PCI $ASPM
$hibPrev  = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled
if ($hibPrev -eq $null) { $hibPrev = 0 }

$backup = [ordered]@{
  Power = @{
    Scheme = $scheme
    USB    = @{ AC = $usbPrev.AC; DC = $usbPrev.DC }
    PCIe   = @{ AC = $pciPrev.AC; DC = $pciPrev.DC }
  }
  HibernateEnabled = $hibPrev
}
$backup | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $BackupJson
Write-Host "Backup saved -> $BackupJson"

# ===== 3) Apply stability tweaks =====
Header "Applying stability tweaks"
try { powercfg -h off | Out-Null } catch { Write-Warning "Failed to change hibernation: $_" }
SetPower $scheme $SUB_PCI $ASPM 0 0
SetPower $scheme $SUB_USB $USB_SEL 0 0

$usbNow = QueryPower $scheme $SUB_USB $USB_SEL
$pciNow = QueryPower $scheme $SUB_PCI $ASPM
Write-Host "USB selective suspend -> AC:$($usbNow.AC) DC:$($usbNow.DC)"
Write-Host "PCIe ASPM             -> AC:$($pciNow.AC) DC:$($pciNow.DC)"

# ===== 4) Remove Intel XTU hooks if present =====
Header "Checking for Intel XTU components"
try { sc.exe stop XTU3SERVICE | Out-Null; sc.exe delete XTU3SERVICE | Out-Null } catch {}

try {
  $pnplines = pnputil.exe /enum-drivers
  for($i=0;$i -lt $pnplines.Length;$i++){
    if($pnplines[$i] -match 'Original Name:\s+(xtu.*\.inf)'){
      # look around the match for the Published Name
      for($j=[Math]::Max(0,$i-6); $j -le [Math]::Min($pnplines.Length-1,$i+6); $j++){
        if($pnplines[$j] -match 'Published Name:\s+(\S+)'){
          $pub = $Matches[1]
          Write-Host "Removing driver package $pub (XTU)"
          try { & pnputil /delete-driver $pub /uninstall /force | Out-Null } catch {}
        }
      }
    }
  }
} catch { Write-Warning "XTU cleanup step skipped: $_" }

Write-Host "`nDone. Consider rebooting to apply everything cleanly." -ForegroundColor Green
Write-Host "Tip: run with -Undo to restore previous power settings and hibernation."
