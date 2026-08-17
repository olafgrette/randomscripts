<#
Installs PowerShell 7 (pwsh) if it's not already there, and points sshd's
DefaultShell registry value at it so new SSH sessions land in pwsh instead
of cmd.exe. Needs admin - relaunches itself elevated if not already.
#>

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "not elevated - relaunching as administrator..."
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$pwshPath = "C:\Program Files\PowerShell\7\pwsh.exe"

if (-not (Test-Path $pwshPath)) {
    # winget's package for this is an msix, which needs the VCLibs UWP
    # runtime - missing on a fresh VM, and the failure it produces ("current
    # system configuration does not support the installation of this
    # package") doesn't say so. The plain MSI sidesteps that dependency
    # entirely.
    Write-Host "downloading PowerShell 7 MSI..."
    $msi = Join-Path $env:TEMP "PowerShell-7.6.5-win-x64.msi"
    Invoke-WebRequest -Uri "https://github.com/PowerShell/PowerShell/releases/download/v7.6.5/PowerShell-7.6.5-win-x64.msi" -OutFile $msi

    Write-Host "installing PowerShell 7..."
    $p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /quiet /norestart" -PassThru -Wait
    if ($p.ExitCode -ne 0) {
        Write-Host "msiexec exited with code $($p.ExitCode)" -ForegroundColor Red
    }
    Remove-Item $msi -ErrorAction SilentlyContinue
} else {
    Write-Host "PowerShell 7 already installed"
}

if (-not (Test-Path $pwshPath)) {
    Write-Host "still not found at $pwshPath after install - aborting shell change" -ForegroundColor Red
    Write-Host "done - press Enter to close"
    Read-Host | Out-Null
    exit 1
}

Write-Host "setting sshd DefaultShell to $pwshPath ..."
New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force | Out-Null
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value $pwshPath -PropertyType String -Force | Out-Null

Write-Host "restarting sshd..."
Restart-Service sshd

Write-Host ""
Write-Host "status:"
Get-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell | Select-Object DefaultShell
Get-Service sshd | Select-Object Name, Status

Write-Host "done - press Enter to close"
Read-Host | Out-Null
