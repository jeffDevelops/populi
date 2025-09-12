# PowerShell script to create multiple Android Virtual Devices (AVDs) for multi-instance testing
# This script will find the correct Android SDK tools and create diverse AVDs

param(
    [switch]$ListOnly = $false
)

# Function to find Android SDK path
function Find-AndroidSDK {
    $PossiblePaths = @(
        "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk",
        "C:\Android\Sdk",
        "C:\Program Files\Android\Android Studio\sdk",
        "$env:ANDROID_HOME",
        "$env:ANDROID_SDK_ROOT"
    )
    
    foreach ($Path in $PossiblePaths) {
        if ($Path -and (Test-Path $Path)) {
            return $Path
        }
    }
    return $null
}

# Function to find avdmanager tool
function Find-AVDManager {
    param([string]$SDKPath)
    
    $PossiblePaths = @(
        "$SDKPath\cmdline-tools\latest\bin\avdmanager.bat",
        "$SDKPath\tools\bin\avdmanager.bat",
        "$SDKPath\cmdline-tools\bin\avdmanager.bat"
    )
    
    foreach ($Path in $PossiblePaths) {
        if (Test-Path $Path) {
            return $Path
        }
    }
    return $null
}

# Find Android SDK
Write-Host "Finding Android SDK..." -ForegroundColor Cyan
$SDKPath = Find-AndroidSDK
if (-not $SDKPath) {
    Write-Error "Android SDK not found. Please install Android Studio or set ANDROID_HOME environment variable."
    exit 1
}
Write-Host "Found Android SDK at: $SDKPath" -ForegroundColor Green

# Find avdmanager tool
Write-Host "Finding avdmanager tool..." -ForegroundColor Cyan
$AVDManagerPath = Find-AVDManager -SDKPath $SDKPath
if (-not $AVDManagerPath) {
    Write-Error "avdmanager tool not found. Please install Android SDK Command Line Tools."
    Write-Host "Install via Android Studio: Tools -> SDK Manager -> SDK Tools -> Android SDK Command-line Tools" -ForegroundColor Yellow
    exit 1
}
Write-Host "Found avdmanager at: $AVDManagerPath" -ForegroundColor Green

# List available device definitions and system images
if ($ListOnly) {
    Write-Host "Available device definitions:" -ForegroundColor Yellow
    & $AVDManagerPath list device
    
    Write-Host "Available system images:" -ForegroundColor Yellow
    & $AVDManagerPath list target
    exit 0
}

# Define AVDs to create (using available Pixel device definitions)
$AVDsToCreate = @(
    @{
        Name = "Pixel_7_API_34";
        SystemImage = "system-images;android-34;google_apis;x86_64";
        Device = "pixel_7";
        Description = "Google Pixel 7"
    },
    @{
        Name = "Pixel_6_API_34";
        SystemImage = "system-images;android-34;google_apis;x86_64";
        Device = "pixel_6";
        Description = "Google Pixel 6"
    },
    @{
        Name = "Pixel_5_API_34";
        SystemImage = "system-images;android-34;google_apis;x86_64";
        Device = "pixel_5";
        Description = "Google Pixel 5"
    },
    @{
        Name = "Pixel_4_API_34";
        SystemImage = "system-images;android-34;google_apis;x86_64";
        Device = "pixel_4";
        Description = "Google Pixel 4"
    },
    @{
        Name = "Pixel_3a_API_34";
        SystemImage = "system-images;android-34;google_apis;x86_64";
        Device = "pixel_3a";
        Description = "Google Pixel 3a"
    },
    @{
        Name = "Pixel_2_API_34";
        SystemImage = "system-images;android-34;google_apis;x86_64";
        Device = "pixel_2";
        Description = "Google Pixel 2"
    }
)

# Check if system images are installed
Write-Host "Checking required system images..." -ForegroundColor Cyan
$SDKManagerPath = $AVDManagerPath -replace "avdmanager.bat", "sdkmanager.bat"

if (Test-Path $SDKManagerPath) {
    Write-Host "Installing required system images..." -ForegroundColor Yellow
    & $SDKManagerPath "system-images;android-34;google_apis;x86_64"
    & $SDKManagerPath "system-images;android-33;google_apis;x86_64"
} else {
    Write-Warning "sdkmanager not found. Please ensure system images are installed via Android Studio."
}

# Create AVDs
Write-Host "Creating Android Virtual Devices..." -ForegroundColor Green
$SuccessfulAVDs = @()
$FailedAVDs = @()

foreach ($AVD in $AVDsToCreate) {
    Write-Host "Creating $($AVD.Name) - $($AVD.Description)..." -ForegroundColor Cyan
    
    try {
        # Check if device definition exists first
        $DeviceListOutput = & $AVDManagerPath list device 2>$null
        $DevicePattern = "*$($AVD.Device)*"
        $DeviceExists = $DeviceListOutput | Where-Object { $_ -like $DevicePattern }
        
        if (-not $DeviceExists) {
            Write-Warning "Device definition '$($AVD.Device)' not found. Skipping $($AVD.Name)."
            $FailedAVDs += $AVD.Name
            continue
        }
        
        # Create the AVD
        $CreateArgs = @(
            "create", "avd",
            "-n", $AVD.Name,
            "-k", $AVD.SystemImage,
            "-d", $AVD.Device,
            "--force"
        )
        
        $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $ProcessInfo.FileName = $AVDManagerPath
        $ProcessInfo.Arguments = $CreateArgs -join " "
        $ProcessInfo.RedirectStandardOutput = $true
        $ProcessInfo.RedirectStandardError = $true
        $ProcessInfo.UseShellExecute = $false
        $ProcessInfo.CreateNoWindow = $true
        
        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $ProcessInfo
        $Process.Start() | Out-Null
        $Process.WaitForExit()
        
        if ($Process.ExitCode -eq 0) {
            Write-Host "Successfully created $($AVD.Name)" -ForegroundColor Green
            $SuccessfulAVDs += $AVD.Name
        } else {
            $ErrorOutput = $Process.StandardError.ReadToEnd()
            Write-Warning "Failed to create $($AVD.Name): $ErrorOutput"
            $FailedAVDs += $AVD.Name
        }
    }
    catch {
        Write-Warning "Error creating $($AVD.Name): $($_.Exception.Message)"
        $FailedAVDs += $AVD.Name
    }
}

# Summary
Write-Host "`nAVD Creation Summary:" -ForegroundColor Cyan
Write-Host "Successfully created: $($SuccessfulAVDs.Count) AVDs" -ForegroundColor Green
if ($SuccessfulAVDs.Count -gt 0) {
    $SuccessfulAVDs | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
}

if ($FailedAVDs.Count -gt 0) {
    Write-Host "Failed to create: $($FailedAVDs.Count) AVDs" -ForegroundColor Red
    $FailedAVDs | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "`nTo see available device definitions, run: .\Setup-Android-AVDs.ps1 -ListOnly" -ForegroundColor Yellow
}

Write-Host "AVD creation complete!" -ForegroundColor Green
Write-Host "You can now run: .\Launch-Multi-Android.ps1 -NumberOfInstances 4" -ForegroundColor Yellow

# List created AVDs
Write-Host "Available AVDs:" -ForegroundColor Cyan
& $AVDManagerPath list avd