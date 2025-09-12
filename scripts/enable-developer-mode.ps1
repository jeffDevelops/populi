# PowerShell script to enable Windows Developer Mode for Tauri Android development
# This is required for symbolic link creation

Write-Host "Enabling Windows Developer Mode for Tauri Android development..." -ForegroundColor Green

try {
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    
    if (-not $isAdmin) {
        Write-Warning "This script needs to be run as Administrator to enable Developer Mode."
        Write-Host "Please:" -ForegroundColor Yellow
        Write-Host "1. Right-click on PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
        Write-Host "2. Run this script again" -ForegroundColor Yellow
        Write-Host "" -ForegroundColor Yellow
        Write-Host "Alternatively, you can enable Developer Mode manually:" -ForegroundColor Yellow
        Write-Host "1. Open Settings (Windows + I)" -ForegroundColor Yellow
        Write-Host "2. Go to Update & Security > For developers" -ForegroundColor Yellow
        Write-Host "3. Turn on 'Developer Mode'" -ForegroundColor Yellow
        exit 1
    }
    
    # Enable Developer Mode via registry
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
    
    # Create the registry key if it doesn't exist
    if (-not (Test-Path $registryPath)) {
        New-Item -Path $registryPath -Force | Out-Null
    }
    
    # Set the values to enable Developer Mode
    Set-ItemProperty -Path $registryPath -Name "AllowDevelopmentWithoutDevLicense" -Value 1 -Type DWord
    Set-ItemProperty -Path $registryPath -Name "AllowAllTrustedApps" -Value 1 -Type DWord
    
    Write-Host "Developer Mode has been enabled successfully!" -ForegroundColor Green
    Write-Host "You may need to restart your computer for changes to take effect." -ForegroundColor Yellow
    
} catch {
    Write-Error "Failed to enable Developer Mode: $($_.Exception.Message)"
    Write-Host "Please enable Developer Mode manually:" -ForegroundColor Yellow
    Write-Host "1. Open Settings (Windows + I)" -ForegroundColor Yellow
    Write-Host "2. Go to Update & Security > For developers" -ForegroundColor Yellow
    Write-Host "3. Turn on 'Developer Mode'" -ForegroundColor Yellow
}
