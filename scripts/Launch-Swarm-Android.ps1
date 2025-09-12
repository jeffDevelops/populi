# PowerShell script to launch a swarm of Tauri app instances in separate Android emulators
# Usage: .\Launch-Swarm-Android.ps1 -NumberOfInstances 3 -Clean $true -Sequential $false -StartServices $true
# If Sequential is $true, will run one instance at a time instead of in parallel
# If StartServices is $true, will start Docker Compose services before launching emulators
# If Clean is $true, will kill existing emulators before launching new ones

param(
    [int]$NumberOfInstances = 2,
    [switch]$Clean,
    [switch]$Sequential,
    [switch]$StartServices,
    [switch]$DryRun
)

# Set default values for switches
if (-not $PSBoundParameters.ContainsKey('Clean')) { $Clean = $true }
if (-not $PSBoundParameters.ContainsKey('Sequential')) { $Sequential = $false }
if (-not $PSBoundParameters.ContainsKey('StartServices')) { $StartServices = $false }

# Note: This script automatically detects available AVDs instead of using a predefined list

# Detect if we're in test mode
$IsTestMode = $DryRun -or $env:VITEST_TEST -eq "true" -or $env:DRY_RUN -eq "true"

if ($IsTestMode) {
    Write-Host "[DRY RUN] Swarm-Android Launch Script - Test Mode" -ForegroundColor Yellow
    Write-Host "[DRY RUN] Parameters: NumberOfInstances=$NumberOfInstances, Clean=$Clean, Sequential=$Sequential, StartServices=$StartServices" -ForegroundColor Yellow
    
    # Suppress Docker and other external tool warnings in test mode
    $env:DOCKER_CLI_HINTS = "false"
    $WarningPreference = "SilentlyContinue"
} else {
    Write-Host "Launching $NumberOfInstances Tauri Android emulator instances in separate terminal windows..." -ForegroundColor Green
}

# Function to generate a unique title for each terminal window
function Get-WindowTitle {
    param(
        [int]$InstanceId,
        [string]$EmulatorName
    )
    return "Tauri Android Emulator #$InstanceId ($EmulatorName)"
}

# Function to start a terminal window with the Android emulator
function Start-TerminalWindow {
    param(
        [int]$InstanceId,
        [string]$EmulatorName,
        [bool]$Clean = $true,
        [bool]$ReadOnly = $false
    )
    
    $Title = Get-WindowTitle -InstanceId $InstanceId -EmulatorName $EmulatorName
    $ScriptPath = Join-Path $PSScriptRoot "Run-Android-Emulator.ps1"
    
    # In test mode, just simulate the action
    if ($IsTestMode) {
        Write-Host "[DRY RUN] Would start terminal window: $Title" -ForegroundColor Yellow
        return
    }
    
    # Use Windows Terminal if available, otherwise fall back to PowerShell
    $WindowsTerminalPath = Get-Command "wt.exe" -ErrorAction SilentlyContinue
    
    if ($WindowsTerminalPath) {
        # Launch with Windows Terminal - use proper escaping for parameters
        Write-Host "Using Windows Terminal for instance $InstanceId" -ForegroundColor Cyan
        $Command = "& '$ScriptPath' -InstanceId $InstanceId -EmulatorName '$EmulatorName'"
        if ($Clean) {
            $Command += " -Clean"
        }
        if ($ReadOnly) {
            $Command += " -ReadOnly"
        }
        Start-Process "wt.exe" -ArgumentList "new-tab", "--title", "`"$Title`"", "powershell.exe", "-NoExit", "-Command", $Command
    } else {
        # Launch with regular PowerShell - use proper escaping for parameters
        Write-Host "Using PowerShell for instance $InstanceId" -ForegroundColor Cyan
        $Command = "& '$ScriptPath' -InstanceId $InstanceId -EmulatorName '$EmulatorName'"
        if ($Clean) {
            $Command += " -Clean"
        }
        if ($ReadOnly) {
            $Command += " -ReadOnly"
        }
        Start-Process "powershell.exe" -ArgumentList "-NoExit", "-Command", $Command
    }
}

# Get the host machine's IP address (works on Windows)
function Get-HostIP {
    try {
        # Try to get IP address that can be reached from other devices
        # First try to get the IP from the default route
        $DefaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Where-Object { $_.NextHop -ne "0.0.0.0" } | Select-Object -First 1
        if ($DefaultRoute) {
            $InterfaceIndex = $DefaultRoute.InterfaceIndex
            $IPAddress = Get-NetIPAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "169.254.*" } | Select-Object -First 1
            if ($IPAddress) {
                return $IPAddress.IPAddress
            }
        }
        
        # Fallback: Get the first non-loopback, non-APIPA IPv4 address
        $NetworkAdapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
            $_.IPAddress -ne "127.0.0.1" -and 
            $_.IPAddress -notlike "169.254.*" -and
            ($_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual")
        } | Select-Object -First 1
        
        if ($NetworkAdapters) {
            return $NetworkAdapters.IPAddress
        }
        
        # If all else fails, use localhost (though this won't work from other devices)
        Write-Warning "Could not determine host IP address. Using localhost, which won't work from emulators."
        return "127.0.0.1"
    }
    catch {
        Write-Warning "Error determining host IP address: $($_.Exception.Message). Using localhost."
        return "127.0.0.1"
    }
}

# Get the host IP address
$HostIP = Get-HostIP

# Main script execution starts here
Write-Host "Starting $NumberOfInstances Android emulator instances..." -ForegroundColor Green
Write-Host "Sequential mode: $Sequential" -ForegroundColor Yellow
Write-Host "Start services: $StartServices" -ForegroundColor Yellow
Write-Host "Host IP address: $HostIP" -ForegroundColor Yellow

# Start Docker Compose services if requested
if ($StartServices) {
    Write-Host "Starting Docker Compose services (signaling server and CoTURN)..." -ForegroundColor Green
    
    # Check if docker-compose is installed
    $DockerCompose = Get-Command "docker-compose" -ErrorAction SilentlyContinue
    if (-not $DockerCompose) {
        Write-Error "docker-compose is not installed. Please install Docker Desktop."
        exit 1
    }
    
    # Update turnserver.conf with the host IP if it exists
    $TurnServerConfig = Join-Path $PSScriptRoot "turnserver.conf"
    if (Test-Path $TurnServerConfig) {
        Write-Host "Updating turnserver.conf with host IP: $HostIP" -ForegroundColor Cyan
        $Content = Get-Content $TurnServerConfig
        $Content = $Content -replace "^external-ip=.*", "external-ip=$HostIP"
        $Content = $Content -replace "^realm=.*", "realm=$HostIP"
        Set-Content -Path $TurnServerConfig -Value $Content
    } else {
        Write-Host "Creating turnserver.conf with host IP: $HostIP" -ForegroundColor Cyan
        @"
listening-port=3478
external-ip=$HostIP
realm=$HostIP
user=riftuser:riftpass
min-port=49152
max-port=65535
verbose
"@ | Set-Content -Path $TurnServerConfig
    }
    
    # Start Docker Compose services
    Push-Location $PSScriptRoot\..
    docker-compose up -d
    Pop-Location
    
    # Wait for services to start
    Write-Host "Waiting for services to start..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
}

# Check if Android SDK is available
$AdbPath = Get-Command "adb" -ErrorAction SilentlyContinue
if (-not $AdbPath) {
    Write-Error "Android SDK (adb) is not installed or not in PATH."
    Write-Host "Please install Android Studio and add the SDK tools to your PATH." -ForegroundColor Yellow
    exit 1
}

$EmulatorPath = Get-Command "emulator" -ErrorAction SilentlyContinue
if (-not $EmulatorPath) {
    Write-Error "Android emulator command is not installed or not in PATH."
    Write-Host "Please install Android Studio and add the emulator tools to your PATH." -ForegroundColor Yellow
    exit 1
}

# Get list of available AVDs
Write-Host "Checking available Android Virtual Devices (AVDs)..." -ForegroundColor Cyan
try {
    $AvailableAVDs = @(& emulator -list-avds 2>$null | Where-Object { $_.Trim() -ne "" })
    if ($AvailableAVDs.Count -eq 0) {
        Write-Error "No Android Virtual Devices (AVDs) found."
        Write-Host "Please create AVDs using Android Studio's AVD Manager." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "Available AVDs:" -ForegroundColor Green
    $AvailableAVDs | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "Total AVDs found: $($AvailableAVDs.Count)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to get list of AVDs: $($_.Exception.Message)"
    exit 1
}

# Note: Pre-booting logic removed - each Run-Android-Emulator.ps1 instance handles its own emulator

# Launch each instance - ensure each uses a different AVD
for ($i = 1; $i -le $NumberOfInstances; $i++) {
    # Select emulator for this instance (ensure different AVDs for each instance)
    if ($i -le $AvailableAVDs.Count) {
        $SelectedEmulator = $AvailableAVDs[$i - 1]
    } else {
        # If we have more instances than AVDs, cycle through but add suffix
        $BaseIndex = ($i - 1) % $AvailableAVDs.Count
        $SelectedEmulator = $AvailableAVDs[$BaseIndex]
        Write-Host "Warning: Instance $i will share AVD $SelectedEmulator with another instance" -ForegroundColor Yellow
    }
    
    if ($IsTestMode) {
        Write-Host "[DRY RUN] Instance $i would use emulator: '$SelectedEmulator'" -ForegroundColor Yellow
    } else {
        Write-Host "Instance $i will use emulator: '$SelectedEmulator'" -ForegroundColor Cyan
    }
    
    # Skip actual execution in test mode
    if ($IsTestMode) {
        if ($Sequential) {
            Write-Host "[DRY RUN] Would launch instance $i directly (sequential mode) with emulator: $SelectedEmulator" -ForegroundColor Yellow
        } else {
            Write-Host "[DRY RUN] Would launch instance $i in new terminal window with emulator: $SelectedEmulator" -ForegroundColor Yellow
        }
        continue
    }
    
    
    if ($Sequential) {
        Write-Host "Launching instance $i directly (sequential mode) with emulator: $SelectedEmulator..." -ForegroundColor Yellow
        $ScriptPath = Join-Path $PSScriptRoot "Run-Android-Emulator.ps1"
        # Use -ReadOnly flag when launching multiple instances to avoid AVD conflicts
        # Pass through test mode flags
        if ($Clean) {
            & $ScriptPath -InstanceId $i -EmulatorName $SelectedEmulator -Clean -ReadOnly:($NumberOfInstances -gt 1) -DryRun:$IsTestMode
        } else {
            & $ScriptPath -InstanceId $i -EmulatorName $SelectedEmulator -ReadOnly:($NumberOfInstances -gt 1) -DryRun:$IsTestMode
        }
        Write-Host "Instance $i completed. Moving to next instance..." -ForegroundColor Green
    } else {
        Write-Host "Launching instance $i in new terminal window with emulator: $SelectedEmulator..." -ForegroundColor Yellow
        Start-TerminalWindow -InstanceId $i -EmulatorName $SelectedEmulator -Clean $Clean -ReadOnly ($NumberOfInstances -gt 1)
        
        # Add a short delay between instances to prevent resource contention
        Write-Host "Waiting for 5 seconds before launching the next instance..." -ForegroundColor Cyan
        Start-Sleep -Seconds 5
    }
}

Write-Host "All $NumberOfInstances Android emulator instances have been launched." -ForegroundColor Green
Write-Host "Each window runs an independent Tauri Android instance." -ForegroundColor Yellow
Write-Host "You can close individual windows to stop specific instances." -ForegroundColor Yellow
