# PowerShell script to set up Android environment and initialize Tauri Android

# Find Android SDK
$PossibleSDKPaths = @(
    "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk",
    "C:\Android\Sdk",
    "C:\Program Files\Android\Android Studio\sdk"
)

$AndroidSDK = $null
foreach ($Path in $PossibleSDKPaths) {
    if (Test-Path $Path) {
        $AndroidSDK = $Path
        break
    }
}

if (-not $AndroidSDK) {
    Write-Error "Android SDK not found. Please install Android Studio first."
    Write-Host "Download from: https://developer.android.com/studio" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found Android SDK at: $AndroidSDK" -ForegroundColor Green

# Set environment variables
$env:ANDROID_HOME = $AndroidSDK
$env:ANDROID_SDK_ROOT = $AndroidSDK
$env:PATH = "$AndroidSDK\platform-tools;$AndroidSDK\tools;$AndroidSDK\tools\bin;$env:PATH"

Write-Host "Set ANDROID_HOME to: $env:ANDROID_HOME" -ForegroundColor Cyan
Write-Host "Set ANDROID_SDK_ROOT to: $env:ANDROID_SDK_ROOT" -ForegroundColor Cyan

# Check for Java
try {
    $JavaVersion = java -version 2>&1 | Select-Object -First 1
    Write-Host "Java found: $JavaVersion" -ForegroundColor Green
} catch {
    Write-Error "Java not found. Please install Java 11 or later."
    Write-Host "Download from: https://adoptium.net/" -ForegroundColor Yellow
    exit 1
}

# Try Tauri Android init
Write-Host "Attempting Tauri Android initialization..." -ForegroundColor Yellow
try {
    bun run tauri android init
    Write-Host "Tauri Android initialization successful!" -ForegroundColor Green
} catch {
    Write-Error "Tauri Android init failed: $($_.Exception.Message)"
    Write-Host "You may need to:" -ForegroundColor Yellow
    Write-Host "1. Install Android Studio and SDK" -ForegroundColor Yellow
    Write-Host "2. Install Java 11 or later" -ForegroundColor Yellow
    Write-Host "3. Accept Android SDK licenses: sdkmanager --licenses" -ForegroundColor Yellow
}
