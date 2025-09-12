# PowerShell script to run a Tauri app instance on an Android emulator with dynamic port configuration
# Usage: .\Run-Android-Emulator.ps1 -InstanceId [instance_id] -EmulatorName [emulator_name] -Clean [clean] -ReadOnly [readonly]

param(
    [int]$InstanceId = 1,
    [string]$EmulatorName = "",
    [switch]$Clean = $false,
    [switch]$ReadOnly = $false,
    [switch]$DryRun = $false
)

# Set default values for switches
if (-not $PSBoundParameters.ContainsKey('Clean')) { $Clean = $true }

# Detect if we're in test mode
$IsTestMode = $DryRun -or $env:VITEST_TEST -eq "true" -or $env:DRY_RUN -eq "true"

if ($IsTestMode) {
    Write-Host "[DRY RUN] Run-Android-Emulator - Test Mode" -ForegroundColor Yellow
    Write-Host "[DRY RUN] Parameters: InstanceId=$InstanceId, EmulatorName='$EmulatorName', Clean=$Clean, ReadOnly=$ReadOnly" -ForegroundColor Yellow
    
    # Suppress warnings in test mode
    $WarningPreference = "SilentlyContinue"
    
    # Exit early in test mode - don't execute any real logic
    Write-Host "[DRY RUN] Would start Tauri Android emulator instance $InstanceId with emulator '$EmulatorName'" -ForegroundColor Yellow
    exit 0
}

# Enable verbose output
$VerbosePreference = "Continue"

# Print initial status immediately
Write-Host "Starting Tauri Android emulator instance $InstanceId" -ForegroundColor Green

# Clean up existing emulators if requested (but avoid ADB server restarts that interfere with other instances)
if ($Clean) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Cleaning up existing emulators..." -ForegroundColor Cyan
    try {
        # Kill any running emulator processes (but don't restart ADB server)
        $EmulatorProcesses = Get-Process | Where-Object {$_.ProcessName -like "*emulator*"}
        if ($EmulatorProcesses) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Found $($EmulatorProcesses.Count) running emulator process(es), terminating..." -ForegroundColor Yellow
            $EmulatorProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator processes terminated." -ForegroundColor Green
        } else {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - No running emulator processes found." -ForegroundColor Green
        }
    } catch {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: Could not clean up existing emulators: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Preserving existing emulators (Clean=false)" -ForegroundColor Cyan
}

# Use base ports that align with Vite config defaults (1420, 1421)
$BaseServerPort = 1420
$BaseHMRPort = 1421

# Calculate ports for this instance with wider spacing (30 ports per instance)
$ServerPort = $BaseServerPort + (($InstanceId - 1) * 30)
$HMRPort = $BaseHMRPort + (($InstanceId - 1) * 30)

# Function to check if a port is available
function Test-PortAvailable {
    param(
        [int]$Port
    )
    
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Checking if port $Port is available..." -ForegroundColor Cyan
    
    try {
        # Try to create a TCP listener on the port
        $Listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
        $Listener.Start()
        $Listener.Stop()
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Port $Port is available" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Port $Port is in use" -ForegroundColor Yellow
        return $false
    }
}

# Check for port conflicts with signaling server (port 3000)
if ($ServerPort -eq 3000) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Port 3000 is reserved for signaling server, adjusting..." -ForegroundColor Yellow
    $ServerPort = 3010
}

# Find available server port with max attempts
$MaxAttempts = 5
$Attempts = 0
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Finding available server port starting from $ServerPort..." -ForegroundColor Cyan
while (-not (Test-PortAvailable -Port $ServerPort) -and $Attempts -lt $MaxAttempts) {
    $Attempts++
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Attempt $Attempts`: Port $ServerPort is in use, trying next port" -ForegroundColor Yellow
    $ServerPort += 2
}

# Find available HMR port with max attempts
$Attempts = 0
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Finding available HMR port starting from $HMRPort..." -ForegroundColor Cyan
while (-not (Test-PortAvailable -Port $HMRPort) -and $Attempts -lt $MaxAttempts) {
    $Attempts++
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Attempt $Attempts`: Port $HMRPort is in use, trying next port" -ForegroundColor Yellow
    $HMRPort += 2
}

Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using ports: SERVER=$ServerPort, HMR=$HMRPort" -ForegroundColor Green

# Get the host machine's IP address (works on Windows)
function Get-HostIP {
    try {
        # Try to get IP address that can be reached from other devices
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
        
        # If all else fails, use localhost
        Write-Warning "Could not determine host IP address. Using localhost."
        return "127.0.0.1"
    }
    catch {
        Write-Warning "Error determining host IP address: $($_.Exception.Message). Using localhost."
        return "127.0.0.1"
    }
}

# Get the host IP address
$HostIP = Get-HostIP
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Host IP address: $HostIP" -ForegroundColor Yellow

# Set environment variables for Vite and Tauri
$env:VITE_INSTANCE_ID = $InstanceId
$env:VITE_SERVER_PORT = $ServerPort
$env:VITE_HMR_PORT = $HMRPort
$env:VITE_HOST_IP = $HostIP
$env:VITE_SIGNALING_URL = "ws://$HostIP`:3000"
$env:VITE_TURN_SERVER = "$HostIP`:3478"
$env:TAURI_DEV_HOST = "$HostIP`:$ServerPort"

# Change to the Tauri app directory
$TauriAppPath = Join-Path $PSScriptRoot "..\apps\tauri"
Push-Location $TauriAppPath

# Create a completely separate project directory for this instance
$ProjectDir = "C:\temp\tauri-android-project-$InstanceId"
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Creating separate project directory for instance $InstanceId at $ProjectDir" -ForegroundColor Cyan

# Remove any existing directory but handle potential Vite dependency errors
if (Test-Path $ProjectDir) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Cleaning existing project directory..." -ForegroundColor Yellow
    # First remove the .vite directory if it exists to prevent dependency errors
    $ViteCachePath = Join-Path $ProjectDir "node_modules\.vite"
    if (Test-Path $ViteCachePath) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Removing .vite directory to prevent dependency errors..." -ForegroundColor Cyan
        Remove-Item -Path $ViteCachePath -Recurse -Force
    }
    # Then remove the entire directory
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Removing old project directory..." -ForegroundColor Cyan
    Remove-Item -Path $ProjectDir -Recurse -Force
}

# Create the project directory
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Creating fresh project directory..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $ProjectDir -Force | Out-Null

# Copy the entire project to the temporary location, excluding build artifacts
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Copying project files to temporary location..." -ForegroundColor Cyan
Write-Host "$(Get-Date -Format 'HH:mm:ss') - This may take a minute, please wait..." -ForegroundColor Yellow

# Use robocopy for efficient copying with exclusions
$SourcePath = Get-Location
$ExcludeDirs = @("node_modules", "target", ".git", ".vite", "dist", "build", ".svelte-kit")
$ExcludeFiles = @("*.log", "*.tmp")

# Build robocopy command
$RobocopyArgs = @(
    $SourcePath.Path,
    $ProjectDir,
    "/E",  # Copy subdirectories including empty ones
    "/XD"  # Exclude directories
) + $ExcludeDirs + @("/XF") + $ExcludeFiles + @("/NFL", "/NDL", "/NJH", "/NJS", "/NC", "/NS")

Start-Process -FilePath "robocopy" -ArgumentList $RobocopyArgs -Wait -NoNewWindow
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Project files copied successfully." -ForegroundColor Green

# Create node_modules symlink to save space and time
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Creating symlink for node_modules..." -ForegroundColor Cyan
$OriginalNodeModules = Join-Path $SourcePath "node_modules"
$InstanceNodeModules = Join-Path $ProjectDir "node_modules"
if (Test-Path $OriginalNodeModules) {
    try {
        New-Item -ItemType SymbolicLink -Path $InstanceNodeModules -Target $OriginalNodeModules -Force -ErrorAction Stop | Out-Null
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - node_modules symlink created." -ForegroundColor Green
    } catch {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Symlink failed (admin required), copying node_modules instead..." -ForegroundColor Yellow
        Copy-Item -Path $OriginalNodeModules -Destination $InstanceNodeModules -Recurse -Force
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - node_modules copied successfully." -ForegroundColor Green
    }
} else {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: Original node_modules not found, skipping symlink." -ForegroundColor Yellow
}

# Set CARGO_TARGET_DIR for isolated Rust builds
$CargoTargetDir = Join-Path $ProjectDir "src-tauri\target"
$env:CARGO_TARGET_DIR = $CargoTargetDir
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Set CARGO_TARGET_DIR to: $CargoTargetDir" -ForegroundColor Green

# Create a dynamic .env file for this instance
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Creating dynamic .env file with host IP and ports..." -ForegroundColor Cyan

# Check if a base .env file exists in the project root
$BaseEnvFile = Join-Path $PSScriptRoot ".env.base"
$InstanceEnvFile = Join-Path $ProjectDir ".env"

if (Test-Path $BaseEnvFile) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Found base .env file, using it as a template" -ForegroundColor Cyan
    # Copy the base .env file first
    Copy-Item $BaseEnvFile $InstanceEnvFile
    
    # Then append the dynamic variables
    @"

# Dynamically generated variables for instance $InstanceId
VITE_INSTANCE_ID=$InstanceId
VITE_SERVER_PORT=$ServerPort
VITE_HMR_PORT=$HMRPort
VITE_HOST_IP=$HostIP
VITE_SIGNALING_URL=ws://$HostIP`:3000
VITE_TURN_SERVER=$HostIP`:3478
VITE_TURN_USERNAME=riftuser
VITE_TURN_CREDENTIAL=riftpass
"@ | Add-Content -Path $InstanceEnvFile
} else {
    # No base .env file found, create a new one with just the dynamic variables
    @"
# Dynamically generated .env file for instance $InstanceId
VITE_INSTANCE_ID=$InstanceId
VITE_SERVER_PORT=$ServerPort
VITE_HMR_PORT=$HMRPort
VITE_HOST_IP=$HostIP
VITE_SIGNALING_URL=ws://$HostIP`:3000
VITE_TURN_SERVER=$HostIP`:3478
VITE_TURN_USERNAME=riftuser
VITE_TURN_CREDENTIAL=riftpass
"@ | Set-Content -Path $InstanceEnvFile
}

Write-Host "$(Get-Date -Format 'HH:mm:ss') - .env file created successfully." -ForegroundColor Green

# Update the Tauri config in the isolated directory with the correct port
$InstanceConfigPath = Join-Path $ProjectDir "src-tauri\tauri.conf.json"
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Updating Tauri config with devUrl: http://0.0.0.0:$ServerPort in $InstanceConfigPath" -ForegroundColor Cyan
$ConfigContent = Get-Content $InstanceConfigPath -Raw
$ConfigContent = $ConfigContent -replace '"devUrl": "http://[^"]*"', "`"devUrl`": `"http://0.0.0.0:$ServerPort`""
Set-Content -Path $InstanceConfigPath -Value $ConfigContent
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Tauri config updated successfully." -ForegroundColor Green

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
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Checking available Android Virtual Devices (AVDs)..." -ForegroundColor Cyan
try {
    $AvailableAVDs = @(& emulator -list-avds 2>$null | Where-Object { $_.Trim() -ne "" })
    if ($AvailableAVDs.Count -eq 0) {
        Write-Error "No Android Virtual Devices (AVDs) found."
        Write-Host "Please create AVDs using Android Studio's AVD Manager." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "Available AVDs:" -ForegroundColor Green
    $AvailableAVDs | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Total AVDs found: $($AvailableAVDs.Count)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to get list of AVDs: $($_.Exception.Message)"
    exit 1
}

# Check if the specified emulator exists and prioritize reliable ones
if ($AvailableAVDs -notcontains $EmulatorName) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: Specified emulator '$EmulatorName' not found." -ForegroundColor Yellow
    # Use the first available AVD as fallback
    $EmulatorName = $AvailableAVDs[0]
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using fallback emulator: $EmulatorName" -ForegroundColor Yellow
}

# Use the specified emulator name without switching (to avoid conflicts between instances)
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using assigned emulator: $EmulatorName" -ForegroundColor Cyan

# Function to check if emulator is running
function Test-EmulatorRunning {
    try {
        $Devices = & adb devices 2>$null
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - ADB devices output: $($Devices -join '; ')" -ForegroundColor Gray
        $RunningEmulators = $Devices | Where-Object { $_ -match "emulator-\d+\s+device" }
        if ($RunningEmulators) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Found running emulator(s): $($RunningEmulators -join '; ')" -ForegroundColor Green
            return $true
        }
        return $false
    }
    catch {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error checking emulator status: $($_.Exception.Message)" -ForegroundColor Yellow
        return $false
    }
}

# Function to boot emulator with retries
function Start-EmulatorWithRetry {
    param(
        [string]$EmulatorName,
        [int]$MaxAttempts = 3
    )
    
    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Boot attempt $Attempt of $MaxAttempts for $EmulatorName..." -ForegroundColor Cyan
        
        # Start emulator with basic method (manual startup showed this works)
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Starting emulator: $EmulatorName" -ForegroundColor Cyan
        if ($ReadOnly) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Command: emulator -avd $EmulatorName -read-only" -ForegroundColor Gray
        } else {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Command: emulator -avd $EmulatorName" -ForegroundColor Gray
        }
        
        try {
            # Create temporary files to capture emulator output
            $StdOutFile = Join-Path $env:TEMP "emulator_stdout_$($EmulatorName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            $StdErrFile = Join-Path $env:TEMP "emulator_stderr_$($EmulatorName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            
            # Start emulator process with output redirection to capture errors
            # Use -read-only flag conditionally when multiple instances are expected
            if ($ReadOnly) {
                $EmulatorArgs = @("-avd", $EmulatorName, "-read-only")
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using -read-only flag for multi-instance support" -ForegroundColor Gray
            } else {
                $EmulatorArgs = @("-avd", $EmulatorName)
            }
            $EmulatorProcess = Start-Process -FilePath "emulator" -ArgumentList $EmulatorArgs -PassThru -RedirectStandardOutput $StdOutFile -RedirectStandardError $StdErrFile -ErrorAction Stop
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator process started with PID: $($EmulatorProcess.Id)" -ForegroundColor Green
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Output logs: $StdOutFile" -ForegroundColor Gray
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error logs: $StdErrFile" -ForegroundColor Gray
            
            # Give emulator time to initialize
            Start-Sleep -Seconds 10
            
            # Check if process is still running
            try {
                $ProcessStillRunning = Get-Process -Id $EmulatorProcess.Id -ErrorAction SilentlyContinue
                if (-not $ProcessStillRunning) {
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator process terminated during startup" -ForegroundColor Red
                    
                    # Read and display error output
                    if (Test-Path $StdErrFile) {
                        $ErrorContent = Get-Content $StdErrFile -Raw
                        if ($ErrorContent) {
                            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator error output:" -ForegroundColor Red
                            Write-Host $ErrorContent -ForegroundColor Yellow
                        }
                    }
                    
                    if (Test-Path $StdOutFile) {
                        $OutputContent = Get-Content $StdOutFile -Raw
                        if ($OutputContent) {
                            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator standard output:" -ForegroundColor Red
                            Write-Host $OutputContent -ForegroundColor Yellow
                        }
                    }
                    
                    continue
                } else {
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator process is running, waiting for boot completion..." -ForegroundColor Green
                }
            }
            catch {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Cannot verify emulator process status" -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Failed to start emulator: $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        
        # Wait for emulator to boot (up to 4 minutes)
        $WaitTime = 0
        $MaxWait = 240
        
        while ($WaitTime -lt $MaxWait) {
            # Check if emulator process is still alive
            try {
                $ProcessStillRunning = Get-Process -Id $EmulatorProcess.Id -ErrorAction SilentlyContinue
                if (-not $ProcessStillRunning) {
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator process $($EmulatorProcess.Id) has terminated unexpectedly!" -ForegroundColor Red
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - This usually indicates an AVD configuration issue or missing system images." -ForegroundColor Yellow
                    break
                } else {
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator process $($EmulatorProcess.Id) is still running" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Cannot check emulator process status" -ForegroundColor Yellow
            }
            
            if (Test-EmulatorRunning) {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator $EmulatorName successfully booted on attempt $Attempt." -ForegroundColor Green
                return $true
            }
            Start-Sleep -Seconds 5
            $WaitTime += 5
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Waiting for emulator to boot... ($WaitTime/$MaxWait seconds)" -ForegroundColor Yellow
        }
        
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator boot attempt $Attempt timed out." -ForegroundColor Yellow
        try { Stop-Process -Id $EmulatorProcess.Id -Force -ErrorAction SilentlyContinue } catch { }
        Start-Sleep -Seconds 10
    }
    
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Failed to boot emulator $EmulatorName after $MaxAttempts attempts." -ForegroundColor Red
    return $false
}

# Check if emulator is already running, if not boot it
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Checking if emulator is already running..." -ForegroundColor Cyan
if (Test-EmulatorRunning) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator is already running, skipping boot process." -ForegroundColor Green
} else {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - No running emulator found, booting emulator $EmulatorName..." -ForegroundColor Cyan
    $BootSuccess = Start-EmulatorWithRetry -EmulatorName $EmulatorName
    if (-not $BootSuccess) {
        Write-Error "Failed to boot emulator after multiple attempts."
        exit 1
    }
}

# Wait a bit longer to ensure the emulator is fully initialized
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator is booted. Waiting for it to fully initialize..." -ForegroundColor Cyan
Start-Sleep -Seconds 30

Write-Host "$(Get-Date -Format 'HH:mm:ss') - Emulator is now booted and ready." -ForegroundColor Green

# Change to the isolated project directory
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Changing to isolated project directory: $ProjectDir" -ForegroundColor Cyan
Pop-Location  # Exit the original tauri directory
Push-Location $ProjectDir
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Current directory: $(Get-Location)" -ForegroundColor Cyan

Write-Host "Starting Tauri Android emulator instance $InstanceId with:" -ForegroundColor Green
Write-Host "  - Emulator: $EmulatorName" -ForegroundColor Yellow
Write-Host "  - Server Port: $ServerPort" -ForegroundColor Yellow
Write-Host "  - HMR Port: $HMRPort" -ForegroundColor Yellow
Write-Host "  - Working Directory: $ProjectDir" -ForegroundColor Yellow
Write-Host "  - Cargo Target Directory: $CargoTargetDir" -ForegroundColor Yellow

# Display environment variables being used
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using the following environment variables:" -ForegroundColor Cyan
Write-Host "  - VITE_INSTANCE_ID: $InstanceId" -ForegroundColor Yellow
Write-Host "  - VITE_SERVER_PORT: $ServerPort" -ForegroundColor Yellow
Write-Host "  - VITE_HMR_PORT: $HMRPort" -ForegroundColor Yellow
Write-Host "  - VITE_HOST_IP: $HostIP" -ForegroundColor Yellow
Write-Host "  - VITE_SIGNALING_URL: ws://$HostIP`:3000" -ForegroundColor Yellow
Write-Host "  - VITE_TURN_SERVER: $HostIP`:3478" -ForegroundColor Yellow
Write-Host "  - CARGO_TARGET_DIR: $CargoTargetDir" -ForegroundColor Yellow

# Run the Tauri app on Android emulator
Write-Host "Running Tauri app for Android..." -ForegroundColor Green
Write-Host "$(Get-Date -Format 'HH:mm:ss') - This may take several minutes for the first run as it builds the app..." -ForegroundColor Yellow

# Function to get available AVDs for instance selection
function Get-AvailableAVDs {
    try {
        Write-Host "Debug: Getting available AVDs for instance selection..." -ForegroundColor Cyan
        
        # Get list of all available AVDs (not just running ones)
        $AvailableAVDs = @(& emulator -list-avds 2>$null | Where-Object { $_.Trim() -ne "" })
        
        if ($AvailableAVDs.Count -eq 0) {
            Write-Warning "No Android Virtual Devices (AVDs) found."
            return @()
        }
        
        Write-Host "Debug: Available AVDs for selection:" -ForegroundColor Cyan
        $AvailableAVDs | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
        
        # Convert to device objects for consistent interface
        $Devices = @()
        foreach ($AvdName in $AvailableAVDs) {
            $Devices += @{
                Id = $AvdName
                Model = $AvdName
                Name = $AvdName
            }
        }
        
        Write-Host "Debug: Prepared $($Devices.Count) AVDs for instance selection" -ForegroundColor Cyan
        return $Devices
    }
    catch {
        Write-Warning "Failed to get available AVDs: $($_.Exception.Message)"
        return @()
    }
}

# Function to select device automatically based on instance ID
function Select-DeviceForInstance {
    param(
        [int]$InstanceId,
        [array]$AvailableDevices
    )
    
    if ($AvailableDevices.Count -eq 0) {
        Write-Warning "No Android devices available"
        return $null
    }
    
    # Use modulo to cycle through available devices
    $DeviceIndex = ($InstanceId - 1) % $AvailableDevices.Count
    $SelectedDevice =$AvailableDevices[$DeviceIndex]
    
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Auto-selected device for instance $InstanceId`: $($SelectedDevice.Name)" -ForegroundColor Green
    return $SelectedDevice
}

try {
    # Get available AVDs for instance selection
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Getting available AVDs for instance selection..." -ForegroundColor Cyan
    $AndroidDevices = Get-AvailableAVDs
    
    if ($AndroidDevices.Count -eq 0) {
        Write-Error "No Android Virtual Devices (AVDs) found. Please create AVDs using Android Studio's AVD Manager."
        exit 1
    }
    
    # Select device for this instance
    $SelectedDevice = Select-DeviceForInstance -InstanceId $InstanceId -AvailableDevices $AndroidDevices
    if (-not $SelectedDevice) {
        Write-Error "Failed to select device for instance $InstanceId"
        exit 1
    }
    
    # Set environment variable for Tauri to use specific device
    $env:ADB_DEVICE_ID = $SelectedDevice.Id
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Set ADB_DEVICE_ID to: $($SelectedDevice.Id)" -ForegroundColor Green
    
    # Use the original project's Tauri CLI directly
    $OriginalProjectPath = Join-Path $PSScriptRoot "..\apps\tauri"
    $TauriCliPath = Join-Path $OriginalProjectPath "node_modules\.bin\tauri.cmd"
    
    if (Test-Path $TauriCliPath) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using Tauri CLI from original project: $TauriCliPath" -ForegroundColor Cyan
        & $TauriCliPath android dev $($SelectedDevice.Id)
    } else {
        # Fallback to running from the original project directory
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Tauri CLI not found at expected path, using original project directory..." -ForegroundColor Yellow
        
        Push-Location $OriginalProjectPath
        try {
            if (Test-Path "bun.lockb") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using bun from original project to run Tauri Android dev..." -ForegroundColor Cyan
                # Pass device as positional argument to avoid interactive prompt
                bun run tauri android dev $($SelectedDevice.Id)
            } elseif (Test-Path "package-lock.json") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using npm from original project to run Tauri Android dev..." -ForegroundColor Cyan
                npm run tauri android dev $($SelectedDevice.Id)
            } else {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Defaulting to bun from original project to run Tauri Android dev..." -ForegroundColor Cyan
                bun run tauri android dev $($SelectedDevice.Id)
            }
        } finally {
            Pop-Location
        }
    }
}
catch {
    Write-Error "Failed to run Tauri Android dev: $($_.Exception.Message)"
    Write-Host "Make sure you have:" -ForegroundColor Yellow
    Write-Host "  1. Bun installed (primary package manager for this project)" -ForegroundColor Yellow
    Write-Host "  2. Rust and Cargo installed" -ForegroundColor Yellow
    Write-Host "  3. Tauri CLI installed (bun install -g @tauri-apps/cli)" -ForegroundColor Yellow
    Write-Host "  4. Android Studio with SDK and NDK installed" -ForegroundColor Yellow
    Write-Host "  5. All project dependencies installed (bun install)" -ForegroundColor Yellow
}
finally {
    # Cleanup - remove the temporary project directory
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Cleaning up temporary project directory..." -ForegroundColor Yellow
    Pop-Location
    if (Test-Path $ProjectDir) {
        try {
            Remove-Item -Path $ProjectDir -Recurse -Force
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Temporary project directory cleaned up successfully." -ForegroundColor Green
        } catch {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: Could not fully clean up temporary directory: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
