<#
One-time setup: installs and enables OpenSSH Server (sshd) as a remote
recovery channel for when the console/GUI becomes unusable. Needs admin - if
run non-elevated, it relaunches itself elevated (one UAC prompt) and exits.
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "not elevated - relaunching as administrator..."
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Write-Host "installing OpenSSH Server capability..."
$cap = Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
if ($cap.State -ne "Installed") {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
} else {
    Write-Host "  already installed"
}

Write-Host "enabling and starting sshd..."
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

Write-Host "checking firewall rule..."
$rule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
if ($rule) {
    # Default rule is scoped to the Private profile only. Virtual/NAT network
    # adapters (VMs, some VPNs) often show up as Public, so an inbound
    # connection can reach Windows and get silently dropped before sshd ever
    # sees it unless this covers Public too.
    Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True -Profile Any
} else {
    New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any | Out-Null
}

Write-Host "installing public key for admin-group login..."
# sshd_config has a Match Group administrators block that redirects admin
# accounts to this file instead of ~/.ssh/authorized_keys - and it refuses
# to use it unless only SYSTEM and Administrators can touch it.
$adminKeysPath = "C:\ProgramData\ssh\administrators_authorized_keys"
$pubKeyPath = "$env:USERPROFILE\.ssh\id_ed25519.pub"
if (Test-Path $pubKeyPath) {
    $pubKey = Get-Content $pubKeyPath
    $exists = (Test-Path $adminKeysPath) -and (Select-String -Path $adminKeysPath -Pattern ([regex]::Escape($pubKey)) -Quiet -ErrorAction SilentlyContinue)
    if (-not $exists) {
        Add-Content -Path $adminKeysPath -Value $pubKey
    }
    icacls $adminKeysPath /inheritance:r | Out-Null
    icacls $adminKeysPath /grant:r "SYSTEM:F" | Out-Null
    icacls $adminKeysPath /grant:r "Administrators:F" | Out-Null
    Write-Host "  installed to $adminKeysPath"
} else {
    Write-Host "  no key at $pubKeyPath - skipped" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "status:"
Get-Service sshd | Select-Object Name, Status, StartType | Format-Table -AutoSize
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" | Select-Object Name, Enabled, Direction, Action | Format-Table -AutoSize

Write-Host "done - press Enter to close"
Read-Host | Out-Null
