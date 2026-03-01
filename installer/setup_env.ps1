# =============================================================================
#  DemucsStudio  —  Environment Setup Script
#
#  Parameters
#  ----------
#  -UseCuda   $true   Install PyTorch with CUDA 12.1  (~2.5 GB)
#             $false  Install PyTorch CPU-only         (~250 MB)
#             (omit)  Auto-detect via nvidia-smi
#
#  -LogFile   Path for the setup log  (default: %TEMP%\demucs_setup.log)
#
#  Can be re-run safely at any time to repair or switch backends.
#  To switch from CPU to CUDA later, run:
#      powershell -File setup_env.ps1 -UseCuda $true
# =============================================================================

param(
    [Parameter(Mandatory=$false)]
    [Nullable[bool]] $UseCuda = $null,

    [string] $LogFile = "$env:TEMP\demucs_setup.log"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ───────────────────────────────────────────────────────────────────

function Log($msg) {
    $ts   = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $LogFile -Value $line
}

function Die($msg) {
    Log "ERROR: $msg"
    [System.Windows.Forms.MessageBox]::Show(
        "$msg`n`nFull log: $LogFile",
        "DemucsStudio Setup Failed",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

function RunCmd([string]$exe, [string]$arguments) {
    Log "  > $exe $arguments"
    $p = Start-Process -FilePath $exe -ArgumentList $arguments `
             -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { Die "$exe exited with code $($p.ExitCode)" }
}

Add-Type -AssemblyName System.Windows.Forms

# ── Log header ────────────────────────────────────────────────────────────────

"" | Set-Content $LogFile
Log "DemucsStudio environment setup"
Log "================================"
Log "User    : $env:USERNAME"
Log "Machine : $env:COMPUTERNAME"
Log "OS      : $(([System.Environment]::OSVersion).VersionString)"

# ── 1. Resolve CUDA choice ────────────────────────────────────────────────────

Log ""
Log "1/5  Resolving PyTorch backend..."

$gpuName  = ""
$hasCuda  = $false

# Always detect the GPU for informational purposes
try {
    $smi = & nvidia-smi --query-gpu=name --format=csv,noheader 2>$null
    if ($LASTEXITCODE -eq 0 -and $smi) {
        $gpuName = $smi.Split("`n")[0].Trim()
        $hasCuda = $true
    }
} catch { }

if ($null -eq $UseCuda) {
    # No explicit choice passed — auto-detect
    $UseCuda = $hasCuda
    if ($UseCuda) {
        Log "     Auto-detected GPU: $gpuName  →  will install CUDA build"
    } else {
        Log "     No NVIDIA GPU found  →  will install CPU-only build"
    }
} else {
    # User made an explicit choice in the installer
    if ($UseCuda -and -not $hasCuda) {
        Log "     WARNING: CUDA selected but no NVIDIA GPU detected ($gpuName)."
        Log "              Proceeding anyway — the app will fall back to CPU at runtime."
    }
    $choice = if ($UseCuda) { "CUDA (GPU)" } else { "CPU-only" }
    $gpu    = if ($gpuName) { $gpuName } else { "not detected" }
    Log "     User choice : $choice"
    Log "     GPU on this machine: $gpu"
}

# ── 2. Python 3.10 ────────────────────────────────────────────────────────────

Log ""
Log "2/5  Checking Python 3.10..."

$pythonTarget = "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe"
$pythonOk     = Test-Path $pythonTarget

if (-not $pythonOk) {
    try {
        $v = & python --version 2>&1
        if ($v -match "3\.10") {
            $pythonTarget = (Get-Command python).Source
            $pythonOk     = $true
            Log "     Found on PATH: $pythonTarget"
        }
    } catch { }
}

if (-not $pythonOk) {
    Log "     Python 3.10 not found — downloading installer..."
    $py310Url = "https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe"
    $py310Ins = "$env:TEMP\python-3.10.11-amd64.exe"

    try {
        Invoke-WebRequest -Uri $py310Url -OutFile $py310Ins -UseBasicParsing
    } catch {
        Die "Failed to download Python 3.10 installer: $_"
    }

    Log "     Installing Python 3.10..."
    RunCmd $py310Ins "/quiet InstallAllUsers=0 PrependPath=0 Include_test=0 Include_launcher=0 TargetDir=`"$env:LOCALAPPDATA\Programs\Python\Python310`""

    if (-not (Test-Path $pythonTarget)) {
        Die "Python installation completed but python.exe not found at: $pythonTarget"
    }
    Log "     Python 3.10 installed."
}

# ── 3. Create venv ────────────────────────────────────────────────────────────

Log ""
Log "3/5  Setting up demucs venv..."

$venvRoot   = "$env:USERPROFILE\demucs_env"
$venvPython = "$venvRoot\Scripts\python.exe"
$venvPip    = "$venvRoot\Scripts\pip.exe"

if (Test-Path $venvPython) {
    Log "     Venv already exists at $venvRoot"
} else {
    Log "     Creating venv at $venvRoot ..."
    RunCmd $pythonTarget "-m venv `"$venvRoot`""
}

Log "     Upgrading pip..."
RunCmd $venvPython "-m pip install --upgrade pip --quiet"

# ── 4. PyTorch + demucs ───────────────────────────────────────────────────────

Log ""
Log "4/5  Installing PyTorch + demucs..."

# Check if torch is already installed AND matches the requested backend
$torchOk      = $false
$torchIsCuda  = $false

try {
    $torchVer    = & $venvPython -c "import torch; print(torch.__version__)" 2>$null
    $torchCudaOk = & $venvPython -c "import torch; print(torch.cuda.is_available())" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $torchOk     = $true
        $torchIsCuda = ($torchCudaOk.Trim() -eq "True")
        Log "     Existing torch $torchVer   cuda_available=$torchIsCuda"
    }
} catch { }

# Reinstall torch if backend choice doesn't match what's installed
if ($torchOk -and ($torchIsCuda -ne $UseCuda)) {
    Log "     Backend mismatch — reinstalling PyTorch for $( if ($UseCuda) { 'CUDA' } else { 'CPU' } )..."
    RunCmd $venvPip "uninstall torch torchaudio -y --quiet"
    $torchOk = $false
}

if (-not $torchOk) {
    if ($UseCuda) {
        Log "     Installing PyTorch CUDA 12.1 build (~2.5 GB — this will take a while)..."
        RunCmd $venvPip "install torch torchaudio --index-url https://download.pytorch.org/whl/cu121 --quiet"
    } else {
        Log "     Installing PyTorch CPU build (~250 MB)..."
        RunCmd $venvPip "install torch torchaudio --index-url https://download.pytorch.org/whl/cpu --quiet"
    }
}

# Demucs
$demucsOk = $false
try {
    $null = & $venvPython -c "import demucs" 2>$null
    if ($LASTEXITCODE -eq 0) { $demucsOk = $true; Log "     demucs already installed." }
} catch { }

if (-not $demucsOk) {
    Log "     Installing demucs..."
    RunCmd $venvPip "install demucs --quiet"
}

# ── 5. ffmpeg ─────────────────────────────────────────────────────────────────

Log ""
Log "5/5  Checking ffmpeg..."

$ffmpegOk = $false
try {
    $null = & ffmpeg -version 2>$null
    if ($LASTEXITCODE -eq 0) { $ffmpegOk = $true; Log "     ffmpeg already on PATH." }
} catch { }

if (-not $ffmpegOk) {
    $wingetOk = $false
    try { $null = Get-Command winget -ErrorAction Stop; $wingetOk = $true } catch { }

    if ($wingetOk) {
        Log "     Installing ffmpeg via winget..."
        try {
            $p = Start-Process "winget" `
                   -ArgumentList "install --id Gyan.FFmpeg --silent --accept-package-agreements --accept-source-agreements" `
                   -Wait -PassThru -NoNewWindow
            if ($p.ExitCode -eq 0) { $ffmpegOk = $true; Log "     ffmpeg installed via winget." }
        } catch { }
    }

    if (-not $ffmpegOk) {
        Log "     Downloading ffmpeg essentials build..."
        $ffmpegDir = "$env:LOCALAPPDATA\ffmpeg"
        $ffmpegZip = "$env:TEMP\ffmpeg-essentials.zip"
        $ffmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"

        try {
            Invoke-WebRequest -Uri $ffmpegUrl -OutFile $ffmpegZip -UseBasicParsing
            Expand-Archive -Path $ffmpegZip -DestinationPath "$env:TEMP\ffmpeg_extract" -Force

            $binDir = Get-ChildItem "$env:TEMP\ffmpeg_extract" -Recurse -Filter "ffmpeg.exe" |
                      Select-Object -First 1 | Split-Path -Parent

            New-Item -ItemType Directory -Force -Path $ffmpegDir | Out-Null
            Copy-Item "$binDir\*" $ffmpegDir -Force

            $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if ($userPath -notlike "*$ffmpegDir*") {
                [Environment]::SetEnvironmentVariable("PATH", "$userPath;$ffmpegDir", "User")
            }

            # Also drop ffmpeg into the venv Scripts so demucs always finds it
            Copy-Item "$ffmpegDir\ffmpeg.exe"  "$venvRoot\Scripts\" -Force
            Copy-Item "$ffmpegDir\ffprobe.exe" "$venvRoot\Scripts\" -Force -ErrorAction SilentlyContinue

            $ffmpegOk = $true
            Log "     ffmpeg installed to $ffmpegDir"
        } catch {
            Log "     WARNING: Could not install ffmpeg automatically: $_"
            Log "     Please install ffmpeg manually: https://ffmpeg.org/download.html"
        }
    }
}

# ── Done ──────────────────────────────────────────────────────────────────────

Log ""
Log "============================================"
Log "Setup complete!"
Log "  Venv    : $venvRoot"
Log "  Backend : $(if ($UseCuda) { 'CUDA (GPU)' } else { 'CPU-only' })"
Log "  GPU     : $(if ($gpuName) { $gpuName } else { 'not detected' })"
Log "  Log     : $LogFile"
Log "============================================"
Log ""
Log "To switch backends later, run:"
Log "  powershell -ExecutionPolicy Bypass -File setup_env.ps1 -UseCuda `$true   (GPU)"
Log "  powershell -ExecutionPolicy Bypass -File setup_env.ps1 -UseCuda `$false  (CPU)"
