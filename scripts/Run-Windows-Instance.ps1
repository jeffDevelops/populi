# PowerShell script to run a Tauri app instance with dynamic port configuration
# Usage: .\Run-Windows-Instance.ps1 -InstanceId [instance_id]

param(
    [int]$InstanceId = 1,
    [int]$ServerPort = 0,
    [int]$HMRPort = 0
)

# Import common functions
. "$PSScriptRoot\Common-Tauri-Functions.ps1"

# Enable verbose output
$VerbosePreference = "Continue"

# Print initial status immediately
Write-Host "Starting Tauri Windows instance $InstanceId" -ForegroundColor Green

# Use provided ports or calculate defaults if not provided
if ($ServerPort -eq 0) {
    # Use base ports that match Tauri's expected devUrl (1420)
    $BaseServerPort = 1420
    $ServerPort = $BaseServerPort + (($InstanceId - 1) * 20)
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - No ServerPort provided, calculated: $ServerPort" -ForegroundColor Yellow
}

if ($HMRPort -eq 0) {
    # Use base HMR port
    $BaseHMRPort = 6000
    $HMRPort = $BaseHMRPort + (($InstanceId - 1) * 20)
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - No HMRPort provided, calculated: $HMRPort" -ForegroundColor Yellow
}

# Get available ports using common function
$PortInfo = Get-AvailablePorts -ServerPort $ServerPort -HMRPort $HMRPort
$ServerPort = $PortInfo.ServerPort
$HMRPort = $PortInfo.HMRPort

# Get the host IP address
$HostIP = Get-HostIP
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Host IP address: $HostIP" -ForegroundColor Yellow

# Set environment variables using common function
Set-ViteEnvironment -InstanceId $InstanceId -ServerPort $ServerPort -HMRPort $HMRPort -HostIP $HostIP

# Change to the Tauri app directory
$TauriAppPath = Join-Path $PSScriptRoot "..\apps\tauri"
Push-Location $TauriAppPath

# Create project instance using common function
$SourcePath = Get-Location
$ProjectDir = New-TauriProjectInstance -InstanceId $InstanceId -Platform "windows" -SourcePath $SourcePath.Path -HostIP $HostIP -ServerPort $ServerPort -HMRPort $HMRPort

if ($null -eq $ProjectDir) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Failed to create project instance. Exiting." -ForegroundColor Red
    Pop-Location
    exit 1
}

Write-Host "Starting Tauri Windows instance $InstanceId with:" -ForegroundColor Green
Write-Host "  - Server Port: $ServerPort" -ForegroundColor Yellow
Write-Host "  - HMR Port: $HMRPort" -ForegroundColor Yellow
Write-Host "  - Working Directory: $ProjectDir" -ForegroundColor Yellow
Write-Host "  - Cargo Target Directory: $CargoTargetDir" -ForegroundColor Yellow

# Create dynamic .env file using common function
New-DynamicEnvFile -ProjectDir $ProjectDir -InstanceId $InstanceId -ServerPort $ServerPort -HMRPort $HMRPort -HostIP $HostIP -ScriptRoot $PSScriptRoot

# Update the Tauri config in the isolated directory with the correct port
$InstanceConfigPath = Join-Path $ProjectDir "src-tauri\tauri.conf.json"
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Updating Tauri config with devUrl: http://localhost:$ServerPort in $InstanceConfigPath" -ForegroundColor Cyan

if (Test-Path $InstanceConfigPath) {
    $ConfigContent = Get-Content $InstanceConfigPath -Raw
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Original config contains: $($ConfigContent -match '"devUrl"')" -ForegroundColor Yellow
    
    # Try to replace existing devUrl first, if it exists
    $UpdatedContent = $ConfigContent -replace '"devUrl":\s*"[^"]*"', "`"devUrl`": `"http://localhost:$ServerPort`""
    
    # If no replacement was made (no existing devUrl), add it to the build section
    if ($UpdatedContent -eq $ConfigContent) {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - No existing devUrl found, adding new devUrl to build section" -ForegroundColor Cyan
        $UpdatedContent = $ConfigContent -replace '("frontendDist":\s*"[^"]*")', "`$1,`n    `"devUrl`": `"http://localhost:$ServerPort`""
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Successfully replaced existing devUrl" -ForegroundColor Green
    }
    
    # Validate JSON before writing
    try {
        $UpdatedContent | ConvertFrom-Json | Out-Null
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - JSON validation passed, writing config file..." -ForegroundColor Green
        # Write without BOM to prevent JSON parsing issues
        [System.IO.File]::WriteAllText($InstanceConfigPath, $UpdatedContent, [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: Generated JSON is invalid: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Keeping original config file unchanged" -ForegroundColor Yellow
        return
    }
    
    # Verify the update
    $VerifyContent = Get-Content $InstanceConfigPath -Raw
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Verification: Looking for devUrl with port $ServerPort" -ForegroundColor Cyan
    $DevUrlLine = $VerifyContent | Select-String '"devUrl"'
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Found devUrl line: $DevUrlLine" -ForegroundColor Cyan
    
    if ($VerifyContent -match '"devUrl":\s*"http://localhost:' + $ServerPort + '"') {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Tauri config updated successfully. devUrl set to http://localhost:$ServerPort" -ForegroundColor Green
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: devUrl update may not have taken effect" -ForegroundColor Yellow
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Expected: http://localhost:$ServerPort" -ForegroundColor Yellow
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Current devUrl in config: $DevUrlLine" -ForegroundColor Yellow
        
        # Try more aggressive update
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Attempting more aggressive config update..." -ForegroundColor Yellow
        $UpdatedContent = $VerifyContent -replace '"devUrl":\s*"[^"]*"', "`"devUrl`": `"http://localhost:$ServerPort`""
        
        # Validate JSON before writing
        try {
            $UpdatedContent | ConvertFrom-Json | Out-Null
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Aggressive update JSON validation passed, writing config file..." -ForegroundColor Green
            # Write without BOM to prevent JSON parsing issues
            [System.IO.File]::WriteAllText($InstanceConfigPath, $UpdatedContent, [System.Text.UTF8Encoding]::new($false))
        } catch {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Error: Aggressive update generated invalid JSON: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Keeping previous config file version" -ForegroundColor Yellow
        }
        
        # Final verification
        $FinalContent = Get-Content $InstanceConfigPath -Raw
        $FinalDevUrl = $FinalContent | Select-String '"devUrl"'
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Final devUrl after aggressive update: $FinalDevUrl" -ForegroundColor Cyan
    }
} else {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Warning: Tauri config file not found at $InstanceConfigPath" -ForegroundColor Yellow
}

# Change to the isolated project directory
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Changing to isolated project directory: $ProjectDir" -ForegroundColor Cyan
Pop-Location  # Exit the original tauri directory
Push-Location $ProjectDir
Write-Host "$(Get-Date -Format 'HH:mm:ss') - Current directory: $(Get-Location)" -ForegroundColor Cyan

# Display environment variables using common function
$CargoTargetDir = Join-Path $ProjectDir "src-tauri\target"
Show-EnvironmentVariables -InstanceId $InstanceId -ServerPort $ServerPort -HMRPort $HMRPort -HostIP $HostIP -CargoTargetDir $CargoTargetDir

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
            
            # Run Tauri from the isolated directory to use the updated config
            # Use the isolated directory's package.json and tauri.conf.json
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Running Tauri from isolated directory to use updated config..." -ForegroundColor Cyan
            
            if (Test-Path "bun.lockb") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using bun to run Tauri dev from isolated directory..." -ForegroundColor Cyan
                bun run tauri dev
            } elseif (Test-Path "package-lock.json") {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Using npm to run Tauri dev from isolated directory..." -ForegroundColor Cyan
                npm run tauri dev
            } else {
                Write-Host "$(Get-Date -Format 'HH:mm:ss') - Defaulting to bun to run Tauri dev from isolated directory..." -ForegroundColor Cyan
                bun run tauri dev
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
    # Cleanup project directory
    Pop-Location
    if ($? -and $null -ne $ProjectDir) {
        Remove-TauriProjectInstance -ProjectDir $ProjectDir
    } else {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Keeping project directory for debugging: $ProjectDir" -ForegroundColor Yellow
    }
}
