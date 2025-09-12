# PowerShell script to run a Tauri app instance with dynamic port configuration
# Usage: .\Run-Windows-Instance.ps1 -InstanceId [instance_id]

param(
    [int]$InstanceId = 1
)

# Enable verbose output
$VerbosePreference = "Continue"

# Print initial status immediately
Write-Host "Starting Tauri Windows instance $InstanceId" -ForegroundColor Green

# Use higher base ports to avoid common conflicts
$BaseServerPort = 5000
$BaseHMRPort = 6000

# Calculate ports for this instance with wider spacing
$ServerPort = $BaseServerPort + (($InstanceId - 1) * 20)
$HMRPort = $BaseHMRPort + (($InstanceId - 1) * 20)

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

# Pre-check if our signaling server is using port 3000
if ($ServerPort -eq 3000) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Port 3000 is reserved for signaling server, skipping" -ForegroundColor Yellow
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

# Set environment variables for Vite
$env:VITE_INSTANCE_ID = $InstanceId
$env:VITE_SERVER_PORT = $ServerPort
$env:VITE_HMR_PORT = $HMRPort
$env:VITE_HOST_IP = $HostIP
$env:VITE_SIGNALING_URL = "ws://$HostIP`:3000"
$env:VITE_TURN_SERVER = "$HostIP`:3478"

# Change to the Tauri app directory
$TauriAppPath = Join-Path $PSScriptRoot "..\apps\tauri"
Push-Location $TauriAppPath

# Create a completely separate project directory for this instance
$ProjectDir = "C:\temp\tauri-windows-project-$InstanceId"
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
    New-Item -ItemType SymbolicLink -Path $InstanceNodeModules -Target $OriginalNodeModules -Force | Out-Null
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - node_modules symlink created." -ForegroundColor Green
} else {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: Original node_modules not found, skipping symlink." -ForegroundColor Yellow
}

# Set CARGO_TARGET_DIR for isolated Rust builds
$CargoTargetDir = Join-Path $ProjectDir "src-tauri\target"
$env:CARGO_TARGET_DIR = $CargoTargetDir
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Set CARGO_TARGET_DIR to: $CargoTargetDir" -ForegroundColor Green

Write-Host "Starting Tauri Windows instance $InstanceId with:" -ForegroundColor Green
Write-Host "  - Server Port: $ServerPort" -ForegroundColor Yellow
Write-Host "  - HMR Port: $HMRPort" -ForegroundColor Yellow
Write-Host "  - Working Directory: $ProjectDir" -ForegroundColor Yellow
Write-Host "  - Cargo Target Directory: $CargoTargetDir" -ForegroundColor Yellow

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
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Updating Tauri config with devUrl: http://localhost:$ServerPort in $InstanceConfigPath" -ForegroundColor Cyan
$ConfigContent = Get-Content $InstanceConfigPath -Raw
$ConfigContent = $ConfigContent -replace '"devUrl": "http://localhost:\d+"', "`"devUrl`": `"http://localhost:$ServerPort`""
Set-Content -Path $InstanceConfigPath -Value $ConfigContent
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Tauri config updated successfully." -ForegroundColor Green

# Change to the isolated project directory
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Changing to isolated project directory: $ProjectDir" -ForegroundColor Cyan
Pop-Location  # Exit the original tauri directory
Push-Location $ProjectDir
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Current directory: $(Get-Location)" -ForegroundColor Cyan

# Display environment variables being used
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using the following environment variables:" -ForegroundColor Cyan
Write-Host "  - VITE_INSTANCE_ID: $InstanceId" -ForegroundColor Yellow
Write-Host "  - VITE_SERVER_PORT: $ServerPort" -ForegroundColor Yellow
Write-Host "  - VITE_HMR_PORT: $HMRPort" -ForegroundColor Yellow
Write-Host "  - VITE_HOST_IP: $HostIP" -ForegroundColor Yellow
Write-Host "  - VITE_SIGNALING_URL: ws://$HostIP`:3000" -ForegroundColor Yellow
Write-Host "  - VITE_TURN_SERVER: $HostIP`:3478" -ForegroundColor Yellow
Write-Host "  - CARGO_TARGET_DIR: $CargoTargetDir" -ForegroundColor Yellow

# Run the Tauri app for Windows
Write-Host "Running Tauri app for Windows..." -ForegroundColor Green

# Use the tauri CLI to run the development server
Write-Host "$(Get-Date -Format 'HH:mm:ss') - This may take several minutes for the first run as it builds the app..." -ForegroundColor Yellow

try {
    # Check if we're running from within WSL or from Windows PowerShell
    $IsRunningFromWSL = $null -ne $env:WSL_DISTRO_NAME
    $IsAccessingWSLPath = $PSScriptRoot -like "*wsl.localhost*"
    
    # Use the original project's node_modules/.bin/tauri directly
    $OriginalProjectPath = Join-Path $PSScriptRoot "..\apps\tauri"
    $TauriCliPath = Join-Path $OriginalProjectPath "node_modules\.bin\tauri.cmd"
    
    if (Test-Path $TauriCliPath) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using Tauri CLI from original project: $TauriCliPath" -ForegroundColor Cyan
        & $TauriCliPath dev
    } else {
        # Fallback to trying bun/npm commands, but use full paths
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Tauri CLI not found at expected path, trying alternative methods..." -ForegroundColor Yellow
        
        if ($IsRunningFromWSL) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Running from within WSL, using direct commands..." -ForegroundColor Yellow
            # We're inside WSL, use direct commands
            if (Test-Path "bun.lockb") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using bun to run Tauri dev..." -ForegroundColor Cyan
                bun run tauri dev
            } elseif (Test-Path "package-lock.json") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using npm to run Tauri dev..." -ForegroundColor Cyan
                npm run tauri dev
            } else {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Defaulting to bun to run Tauri dev..." -ForegroundColor Cyan
                bun run tauri dev
            }
        } elseif ($IsAccessingWSLPath) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Accessing WSL path from Windows, using WSL commands..." -ForegroundColor Yellow
            # We're in Windows PowerShell accessing WSL files
            if (Test-Path "bun.lockb") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using WSL bun to run Tauri dev..." -ForegroundColor Cyan
                wsl bun run tauri dev
            } elseif (Test-Path "package-lock.json") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using WSL npm to run Tauri dev..." -ForegroundColor Cyan
                wsl npm run tauri dev
            } else {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Defaulting to WSL bun to run Tauri dev..." -ForegroundColor Cyan
                wsl bun run tauri dev
            }
        } else {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using native Windows commands..." -ForegroundColor Yellow
            # Native Windows environment - try using the original project's bun
            Push-Location $OriginalProjectPath
            try {
                if (Test-Path "bun.lockb") {
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using bun from original project to run Tauri dev..." -ForegroundColor Cyan
                    $env:TAURI_DEV_WATCHER_IGNORE_FILE = Join-Path $ProjectDir ".taurignore"
                    bun run tauri dev
                } elseif (Test-Path "package-lock.json") {
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using npm from original project to run Tauri dev..." -ForegroundColor Cyan
                    npm run tauri dev
                } else {
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Defaulting to bun from original project to run Tauri dev..." -ForegroundColor Cyan
                    bun run tauri dev
                }
            } finally {
                Pop-Location
            }
        }
    }
}
catch {
    Write-Error "Failed to run Tauri dev: $($_.Exception.Message)"
    Write-Host "Make sure you have:" -ForegroundColor Yellow
    Write-Host "  1. Bun installed (primary package manager for this project)" -ForegroundColor Yellow
    Write-Host "  2. Rust and Cargo installed" -ForegroundColor Yellow
    Write-Host "  3. Tauri CLI installed (bun install -g @tauri-apps/cli)" -ForegroundColor Yellow
    Write-Host "  4. All project dependencies installed (bun install)" -ForegroundColor Yellow
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
