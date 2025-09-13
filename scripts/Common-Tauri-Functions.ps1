# Common PowerShell functions for Tauri multi-instance scripts
# Shared between Run-Android-Emulator.ps1 and Run-Windows-Instance.ps1

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
        Write-Warning "Could not determine host IP address. Using localhost, which won't work from other devices."
        return "127.0.0.1"
    }
    catch {
        Write-Warning "Error determining host IP address: $($_.Exception.Message). Using localhost."
        return "127.0.0.1"
    }
}

# Function to find available ports with conflict avoidance
function Get-AvailablePorts {
    param(
        [int]$ServerPort,
        [int]$HMRPort,
        [int]$MaxAttempts = 5
    )
    
    # Pre-check if our signaling server is using port 3000
    if ($ServerPort -eq 3000) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Port 3000 is reserved for signaling server, skipping" -ForegroundColor Yellow
        $ServerPort = 3010
    }
    
    # Find available server port with max attempts
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
    
    return @{
        ServerPort = $ServerPort
        HMRPort = $HMRPort
    }
}

# Function to create isolated project directory with common setup
function New-TauriProjectInstance {
    param(
        [int]$InstanceId,
        [string]$Platform, # "android" or "windows"
        [string]$SourcePath,
        [string]$HostIP,
        [int]$ServerPort,
        [int]$HMRPort
    )
    
    # Create a completely separate project directory for this instance
    $ProjectDir = "C:\temp\tauri-$Platform-project-$InstanceId"
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
    $ExcludeDirs = @("node_modules", "target", ".git", ".vite", "dist", "build", ".svelte-kit")
    $ExcludeFiles = @("*.log", "*.tmp")
    
    # Build robocopy command - use simple approach like Android script
    $RobocopyArgs = @(
        "`"$SourcePath`"",
        "`"$ProjectDir`"",
        "/E",  # Copy subdirectories including empty ones
        "/XD"  # Exclude directories
    ) + $ExcludeDirs + @("/XF") + $ExcludeFiles
    
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Robocopy command: robocopy `"$SourcePath`" `"$ProjectDir`" /E /XD $($ExcludeDirs -join ' ') /XF $($ExcludeFiles -join ' ')" -ForegroundColor Cyan
    $RobocopyResult = Start-Process -FilePath "robocopy" -ArgumentList $RobocopyArgs -Wait -NoNewWindow -PassThru
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Robocopy exit code: $($RobocopyResult.ExitCode)" -ForegroundColor Cyan
    
    if ($RobocopyResult.ExitCode -le 7) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Project files copied successfully." -ForegroundColor Green
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: Robocopy failed with exit code $($RobocopyResult.ExitCode)" -ForegroundColor Red
        return $null
    }
    
    # Verify critical files were copied
    $CriticalFiles = @("package.json", "vite.config.js", "src-tauri\tauri.conf.json")
    foreach ($File in $CriticalFiles) {
        $FilePath = Join-Path $ProjectDir $File
        if (-not (Test-Path $FilePath)) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: Critical file missing: $File" -ForegroundColor Red
            return $null
        }
    }
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - All critical files verified." -ForegroundColor Green
    
    # Handle monorepo structure - check for node_modules in multiple locations
    $OriginalNodeModules = Join-Path $SourcePath "node_modules"
    $RootNodeModules = Join-Path (Split-Path (Split-Path $SourcePath -Parent) -Parent) "node_modules"  # Go up two levels to root
    $InstanceNodeModules = Join-Path $ProjectDir "node_modules"
    
    # Determine which node_modules to use (prefer local, fallback to root)
    $NodeModulesToUse = $null
    if (Test-Path $OriginalNodeModules) {
        $LocalModulesCount = (Get-ChildItem $OriginalNodeModules -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.bin' -and $_.Name -ne '.vite-temp' }).Count
        if ($LocalModulesCount -gt 2) {
            $NodeModulesToUse = $OriginalNodeModules
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using local node_modules with $LocalModulesCount packages" -ForegroundColor Green
        }
    }
    
    if (-not $NodeModulesToUse -and (Test-Path $RootNodeModules)) {
        $RootModulesCount = (Get-ChildItem $RootNodeModules -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.bin' -and $_.Name -ne '.vite-temp' }).Count
        if ($RootModulesCount -gt 10) {
            $NodeModulesToUse = $RootNodeModules
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using root monorepo node_modules with $RootModulesCount packages" -ForegroundColor Green
        }
    }
    
    if (-not $NodeModulesToUse) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - No suitable node_modules found. Installing dependencies..." -ForegroundColor Yellow
        
        # Try installing in root first (for monorepo), then local
        $InstallLocation = if (Test-Path (Join-Path (Split-Path (Split-Path $SourcePath -Parent) -Parent) "package.json")) { 
            Split-Path (Split-Path $SourcePath -Parent) -Parent 
        } else { 
            $SourcePath 
        }
        
        Push-Location $InstallLocation
        try {
            if (Test-Path "bun.lockb") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Running bun install in $InstallLocation..." -ForegroundColor Cyan
                bun install
            } elseif (Test-Path "package-lock.json") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Running npm install in $InstallLocation..." -ForegroundColor Cyan
                npm install
            } else {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Defaulting to bun install in $InstallLocation..." -ForegroundColor Cyan
                bun install
            }
            
            # Re-check for node_modules after installation
            if (Test-Path $RootNodeModules) {
                $NodeModulesToUse = $RootNodeModules
            } elseif (Test-Path $OriginalNodeModules) {
                $NodeModulesToUse = $OriginalNodeModules
            }
        } catch {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: Failed to install dependencies: $($_.Exception.Message)" -ForegroundColor Red
            Pop-Location
            return $null
        } finally {
            Pop-Location
        }
        
        if (-not $NodeModulesToUse) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: Dependency installation failed" -ForegroundColor Red
            return $null
        }
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Dependencies installed successfully." -ForegroundColor Green
    }
    
    # Create node_modules symlink to save space and time
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Creating symlink for node_modules from $NodeModulesToUse..." -ForegroundColor Cyan
    try {
        New-Item -ItemType SymbolicLink -Path $InstanceNodeModules -Target $NodeModulesToUse -Force -ErrorAction Stop | Out-Null
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - node_modules symlink created." -ForegroundColor Green
    } catch {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Symlink failed (admin required), copying node_modules instead..." -ForegroundColor Yellow
        try {
            Copy-Item -Path $NodeModulesToUse -Destination $InstanceNodeModules -Recurse -Force -ErrorAction Stop
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - node_modules copied successfully." -ForegroundColor Green
        } catch {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: Failed to copy node_modules: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    
    # Verify node_modules was created
    if (-not (Test-Path $InstanceNodeModules)) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: node_modules was not created in isolated directory" -ForegroundColor Red
        return $null
    }
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - node_modules setup verified." -ForegroundColor Green
    
    # Set shared CARGO_TARGET_DIR for Rust compilation caching
    # Use a shared cache directory to avoid recompiling when only JS changes
    $SharedCargoTargetDir = Join-Path $env:TEMP "populi-cargo-cache"
    if (-not (Test-Path $SharedCargoTargetDir)) {
        New-Item -ItemType Directory -Path $SharedCargoTargetDir -Force | Out-Null
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Created shared Cargo cache directory: $SharedCargoTargetDir" -ForegroundColor Green
    }
    $env:CARGO_TARGET_DIR = $SharedCargoTargetDir
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using shared CARGO_TARGET_DIR for compilation caching: $SharedCargoTargetDir" -ForegroundColor Green
    
    # Update Vite configuration to ensure proper host binding
    $ViteConfigPath = Join-Path $ProjectDir "vite.config.js"
    if (Test-Path $ViteConfigPath) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Updating Vite config for proper host binding..." -ForegroundColor Cyan
        $ViteConfigContent = Get-Content $ViteConfigPath -Raw
        
        # Replace the host configuration to match Android solution approach
        $UpdatedViteConfig = $ViteConfigContent -replace 'host: "0\.0\.0\.0"', 'host: host || "0.0.0.0"'
        
        Set-Content -Path $ViteConfigPath -Value $UpdatedViteConfig -Encoding UTF8
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Vite config updated for proper host binding." -ForegroundColor Green
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: vite.config.js not found at $ViteConfigPath" -ForegroundColor Yellow
    }
    
    # Generate SvelteKit artifacts if missing
    $SvelteKitDir = Join-Path $ProjectDir ".svelte-kit"
    $SvelteKitTsConfig = Join-Path $SvelteKitDir "tsconfig.json"
    
    if (-not (Test-Path $SvelteKitTsConfig)) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Missing .svelte-kit/tsconfig.json, generating SvelteKit artifacts..." -ForegroundColor Cyan
        
        # Create .svelte-kit directory if it doesn't exist
        if (-not (Test-Path $SvelteKitDir)) {
            New-Item -ItemType Directory -Path $SvelteKitDir -Force | Out-Null
        }
        
        # Run SvelteKit sync to generate missing files
        try {
            Push-Location $ProjectDir
            if (Test-Path "bun.lockb") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Running bun run svelte-kit sync to generate SvelteKit artifacts..." -ForegroundColor Cyan
                bun run svelte-kit sync
            } else {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Running npx svelte-kit sync to generate SvelteKit artifacts..." -ForegroundColor Cyan
                npx svelte-kit sync
            }
            
            # Verify the tsconfig was created
            if (Test-Path $SvelteKitTsConfig) {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - SvelteKit tsconfig.json generated successfully." -ForegroundColor Green
            } else {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: SvelteKit sync completed but tsconfig.json still missing." -ForegroundColor Yellow
                # Try alternative approach - copy from original if it exists
                $OriginalSvelteKitTsConfig = Join-Path $SourcePath ".svelte-kit\tsconfig.json"
                if (Test-Path $OriginalSvelteKitTsConfig) {
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Copying .svelte-kit directory from original project..." -ForegroundColor Cyan
                    $OriginalSvelteKitDir = Join-Path $SourcePath ".svelte-kit"
                    Copy-Item -Path $OriginalSvelteKitDir -Destination $ProjectDir -Recurse -Force
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - .svelte-kit directory copied from original project." -ForegroundColor Green
                }
            }
        } catch {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: Failed to run SvelteKit sync: $($_.Exception.Message)" -ForegroundColor Yellow
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - SvelteKit tsconfig.json already exists." -ForegroundColor Green
    }
    
    # Verify critical packages are accessible in the source node_modules
    $VitePackagePath = Join-Path $NodeModulesToUse "vite"
    $SvelteKitPackagePath = Join-Path $NodeModulesToUse "@sveltejs\kit"
    
    if (-not (Test-Path $VitePackagePath)) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: Vite package not found in source node_modules at $NodeModulesToUse" -ForegroundColor Red
        return $null
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Vite package found in source node_modules." -ForegroundColor Green
    }
    
    if (-not (Test-Path $SvelteKitPackagePath)) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: SvelteKit package not found in source node_modules at $NodeModulesToUse" -ForegroundColor Red
        return $null
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - SvelteKit package found in source node_modules." -ForegroundColor Green
    }
    
    # Verify the instance node_modules was created successfully
    if (-not (Test-Path $InstanceNodeModules)) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: Instance node_modules was not created successfully" -ForegroundColor Red
        return $null
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Instance node_modules created successfully." -ForegroundColor Green
    }
    
    return $ProjectDir
}

# Function to set up environment variables for Vite
function Set-ViteEnvironment {
    param(
        [int]$InstanceId,
        [int]$ServerPort,
        [int]$HMRPort,
        [string]$HostIP
    )
    
    # Set environment variables for Vite
    $env:VITE_INSTANCE_ID = $InstanceId
    $env:VITE_SERVER_PORT = $ServerPort
    $env:VITE_HMR_PORT = $HMRPort
    $env:VITE_HOST_IP = $HostIP
    $env:VITE_SIGNALING_URL = "ws://$HostIP`:3000"
    $env:VITE_TURN_SERVER = "$HostIP`:3478"
    # Don't set TAURI_DEV_HOST - let Vite bind to 0.0.0.0 for Windows multi-instance support
}

# Function to create dynamic .env file
function New-DynamicEnvFile {
    param(
        [string]$ProjectDir,
        [int]$InstanceId,
        [int]$ServerPort,
        [int]$HMRPort,
        [string]$HostIP,
        [string]$ScriptRoot
    )
    
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Creating dynamic .env file with host IP and ports..." -ForegroundColor Cyan
    
    # Check if a base .env file exists in the project root
    $BaseEnvFile = Join-Path $ScriptRoot ".env.base"
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
}

# Function to display environment variables
function Show-EnvironmentVariables {
    param(
        [int]$InstanceId,
        [int]$ServerPort,
        [int]$HMRPort,
        [string]$HostIP,
        [string]$CargoTargetDir
    )
    
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using the following environment variables:" -ForegroundColor Cyan
    Write-Host "  - VITE_INSTANCE_ID: $InstanceId" -ForegroundColor Yellow
    Write-Host "  - VITE_SERVER_PORT: $ServerPort" -ForegroundColor Yellow
    Write-Host "  - VITE_HMR_PORT: $HMRPort" -ForegroundColor Yellow
    Write-Host "  - VITE_HOST_IP: $HostIP" -ForegroundColor Yellow
    Write-Host "  - VITE_SIGNALING_URL: ws://$HostIP`:3000" -ForegroundColor Yellow
    Write-Host "  - VITE_TURN_SERVER: $HostIP`:3478" -ForegroundColor Yellow
    Write-Host "  - CARGO_TARGET_DIR: $SharedCargoTargetDir" -ForegroundColor Yellow
}

# Function to clean up temporary project directory
function Remove-TauriProjectInstance {
    param(
        [string]$ProjectDir
    )
    
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Cleaning up temporary project directory..." -ForegroundColor Yellow
    if (Test-Path $ProjectDir) {
        try {
            # First, try to kill any processes that might be using files in the directory
            $ProcessesToKill = @("node", "bun", "vite", "tauri", "cargo", "rustc", "propopulo")
            foreach ($ProcessName in $ProcessesToKill) {
                $Processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Where-Object {
                    $_.Path -and $_.Path.StartsWith($ProjectDir, [System.StringComparison]::OrdinalIgnoreCase)
                }
                if ($Processes) {
                    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Stopping $($Processes.Count) $ProcessName process(es) using project directory..." -ForegroundColor Cyan
                    $Processes | Stop-Process -Force -ErrorAction SilentlyContinue
                }
            }
            
            # Wait a moment for processes to fully terminate
            Start-Sleep -Seconds 2
            
            # Try to remove the directory
            Remove-Item -Path $ProjectDir -Recurse -Force -ErrorAction Stop
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Temporary project directory cleaned up successfully." -ForegroundColor Green
        } catch {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: Could not fully clean up temporary directory: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Directory will be cleaned up on next run or can be manually deleted: $ProjectDir" -ForegroundColor Yellow
        }
    }
}
