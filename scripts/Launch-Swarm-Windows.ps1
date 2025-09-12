# PowerShell script to launch a swarm of Tauri app instances on Windows separate Windows terminals
# Usage: .\Launch-Swarm-Windows.ps1 -NumberOfInstances 3 -Clean $true -Sequential $false] [StartServices]
# If Sequential is $true, will run one instance at a time instead of in parallel
# If StartServices is $true, will start Docker Compose services before launching instances

param(
    [int]$NumberOfInstances = 2,
    [bool]$Sequential = $false,
    [bool]$StartServices = $false
)

# Note: This script preserves existing processes by default

Write-Host "Launching $NumberOfInstances Tauri Windows instances in separate terminal windows..." -ForegroundColor Green

# Function to generate a unique title for each terminal window
function Get-WindowTitle {
    param(
        [int]$InstanceId
    )
    return "Tauri Windows Instance #$InstanceId"
}

# Function to start a terminal window with the Tauri app
function Start-TerminalWindow {
    param(
        [int]$InstanceId
    )
    
    $Title = Get-WindowTitle -InstanceId $InstanceId
    $ScriptPath = Join-Path $PSScriptRoot "Run-Windows-Instance.ps1"
    
    # Use Windows Terminal if available, otherwise fall back to PowerShell
    $WindowsTerminalPath = Get-Command "wt.exe" -ErrorAction SilentlyContinue
    
    if ($WindowsTerminalPath) {
        # Launch with Windows Terminal
        Write-Host "Using Windows Terminal for instance $InstanceId" -ForegroundColor Cyan
        Start-Process "wt.exe" -ArgumentList "new-tab", "--title", "`"$Title`"", "powershell.exe", "-NoExit", "-Command", "& `"$ScriptPath`" -InstanceId $InstanceId"
    } else {
        # Launch with regular PowerShell
        Write-Host "Using PowerShell for instance $InstanceId" -ForegroundColor Cyan
        Start-Process "powershell.exe" -ArgumentList "-NoExit", "-Command", "& `"$ScriptPath`" -InstanceId $InstanceId"
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
            $_.PrefixOrigin -eq "Dhcp" -or $_.PrefixOrigin -eq "Manual"
        } | Select-Object -First 1
        
        if ($NetworkAdapters) {
            return $NetworkAdapters.IPAddress
        }
        
        # If all else fails, use localhost (though this won't work from other devices)
        Write-Warning "Could not determine host IP address. Using localhost, which won't work from other devices."
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
Write-Host "Starting $NumberOfInstances Windows instances..." -ForegroundColor Green
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

# Clean old build artifacts to prevent conflicts with renamed project
Write-Host "Cleaning old build artifacts to prevent conflicts..." -ForegroundColor Green
$TauriAppPath = Join-Path $PSScriptRoot "..\apps\tauri"
Push-Location $TauriAppPath

# Clean Vite cache to prevent dependency errors
Write-Host "Cleaning Vite cache to prevent dependency errors..." -ForegroundColor Cyan
$ViteCachePath = Join-Path $TauriAppPath "node_modules\.vite"
if (Test-Path $ViteCachePath) {
    Remove-Item -Path $ViteCachePath -Recurse -Force
    Write-Host "Vite cache cleaned." -ForegroundColor Green
}

# Clean old Rust build artifacts (especially old rift.exe)
Write-Host "Cleaning old Rust build artifacts..." -ForegroundColor Cyan
$TargetPath = Join-Path $TauriAppPath "src-tauri\target"
if (Test-Path $TargetPath) {
    try {
        # Try to remove the entire target directory
        Remove-Item -Path $TargetPath -Recurse -Force
        Write-Host "Old target directory cleaned successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Warning: Could not fully clean target directory. Trying to remove specific files..." -ForegroundColor Yellow
        # Try to remove specific problematic files
        $DebugPath = Join-Path $TargetPath "debug"
        if (Test-Path $DebugPath) {
            Get-ChildItem -Path $DebugPath -Filter "rift*" -File | ForEach-Object {
                try {
                    Remove-Item -Path $_.FullName -Force
                    Write-Host "Removed old file: $($_.Name)" -ForegroundColor Green
                }
                catch {
                    Write-Host "Warning: Could not remove $($_.Name): $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }
}

Write-Host "Build artifact cleanup completed. Each instance will build in its own isolated directory." -ForegroundColor Green

Pop-Location

# Launch each instance
for ($i = 1; $i -le $NumberOfInstances; $i++) {
    if ($Sequential) {
        Write-Host "Launching instance $i directly (sequential mode)..." -ForegroundColor Yellow
        $ScriptPath = Join-Path $PSScriptRoot "Run-Windows-Instance.ps1"
        & $ScriptPath -InstanceId $i
        Write-Host "Instance $i completed. Moving to next instance..." -ForegroundColor Green
    } else {
        Write-Host "Launching instance $i in new terminal window..." -ForegroundColor Yellow
        Start-TerminalWindow -InstanceId $i
        
        # Add a short delay between instances to prevent resource contention
        Write-Host "Waiting for 5 seconds before launching the next instance..." -ForegroundColor Cyan
        Start-Sleep -Seconds 5
    }
}

Write-Host "All $NumberOfInstances Windows instances have been launched." -ForegroundColor Green
Write-Host "Each window runs an independent Tauri Windows instance." -ForegroundColor Yellow
Write-Host "You can close individual windows to stop specific instances." -ForegroundColor Yellow
