# Building the DemucsStudio Installer

## Prerequisites (on your build machine)

- **Inno Setup 6** — https://jrsoftware.org/isinfo.php  
- **.NET 8 SDK** — https://dotnet.microsoft.com/en-us/download/dotnet/8.0

---

## Step 1 — Publish the app

Open a terminal in your project root (`DemucsGUI/`) and run:

```powershell
dotnet publish -c Release -r win-x64 --self-contained false -o bin\publish
```

This produces a lean publish folder that relies on the .NET runtime being installed separately (handled by the installer).

---

## Step 2 — Download the .NET 8 Desktop Runtime

1. Go to https://dotnet.microsoft.com/en-us/download/dotnet/8.0  
2. Under **".NET Desktop Runtime 8.x"**, pick **Windows → x64 → Installer**  
3. Save the file as:

```
installer\redist\dotnet8-desktop-runtime-x64.exe
```

If you skip this step, comment out the `Source:` line for it in `DemucsStudio.iss` — the app will then require users to have .NET 8 pre-installed.

---

## Step 3 — Your project folder should look like this

```
DemucsGUI/
├── DemucsStudio.iss          ← the installer script
├── App.xaml
├── App.xaml.cs
├── MainWindow.xaml
├── MainWindow.xaml.cs
├── DemucsService.cs
├── DemucsGUI.csproj
├── bin\
│   └── publish\              ← output of dotnet publish
│       ├── DemucsStudio.exe
│       └── ...
└── installer\
    ├── setup_env.ps1         ← Python/venv setup script
    ├── BUILD.md              ← this file
    └── redist\
        └── dotnet8-desktop-runtime-x64.exe
```

---

## Step 4 — Build the installer

**Option A — GUI:**  
Right-click `DemucsStudio.iss` → *Compile with Inno Setup*

**Option B — Command line:**
```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" DemucsStudio.iss
```

Output: `installer\Output\DemucsStudio_Setup.exe`

---

## What the installer does on the user's machine

| Step | What happens |
|------|-------------|
| 1 | Copies `DemucsStudio.exe` + files to `C:\Program Files\DemucsStudio\` |
| 2 | Installs **.NET 8 Desktop Runtime** (skipped if already present) |
| 3 | Detects NVIDIA GPU via `nvidia-smi` |
| 4 | Downloads and installs **Python 3.10** to `%LOCALAPPDATA%\Programs\Python\Python310\` (skipped if present) |
| 5 | Creates a Python venv at **`%USERPROFILE%\demucs_env`** |
| 6 | Installs **PyTorch** — CUDA 12.1 build if GPU found (~2.5 GB), CPU-only otherwise (~250 MB) |
| 7 | Installs **demucs** |
| 8 | Installs **ffmpeg** via winget, or downloads manually as fallback |
| 9 | Creates Start Menu + optional desktop shortcut |

The uninstaller offers to remove the venv folder (~3-4 GB) when uninstalling.

---

## Sharing with users

Send them the single file `DemucsStudio_Setup.exe`.  
They need an internet connection during install for the PyTorch/demucs download.  
Total install time: **5–15 minutes** depending on GPU choice and internet speed.

---

## Troubleshooting

If the Python environment step fails, users can re-run it manually:
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\DemucsStudio\setup_env.ps1"
```
The full log is at `%TEMP%\demucs_setup.log`.
