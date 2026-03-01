<div align="center">

# 🎵 DemucsStudio

**A clean Windows GUI for [Demucs](https://github.com/facebookresearch/demucs) — the state-of-the-art AI audio source separation library by Meta Research.**

![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue?style=flat-square)
![.NET](https://img.shields.io/badge/.NET-8.0-512BD4?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

</div>

---

## What is Demucs?

[Demucs](https://github.com/facebookresearch/demucs) is an open-source AI model developed by **Meta Research** that separates a mixed audio track into its individual components — vocals, drums, bass, and other instrumentation — with remarkable accuracy.

It works by running your audio through a deep neural network trained on thousands of songs. Unlike older tools that use frequency masking, Demucs operates in the waveform domain, which means the separated stems sound clean and natural rather than metallic or phase-distorted.

**What you can do with it:**

- Extract clean **vocal stems** for remixing, karaoke, or transcription
- Isolate **drum tracks** for practice or replacement
- Pull out **bass lines** for transcription or re-arrangement
- Get an **instrumental version** of any song
- Separate all four stems at once for full remix capability

---

## What is DemucsStudio?

Demucs is a command-line tool. DemucsStudio wraps it in a modern Windows desktop application so you don't need to touch a terminal.

<div align="center">

![Screenshot placeholder](docs/screenshot.png)

</div>

### Features

**Simple file selection**
Browse for any audio file and choose where the separated stems are saved. The output folder is auto-filled alongside your input file to keep things tidy.

**Two separation modes**
- **Full Separation** — splits into four stems: Vocals, Drums, Bass, Other
- **2-Stem Split** — produces Vocals and Instrumental only (faster)

**Eight model choices**
| Model | Description |
|---|---|
| `htdemucs` | Default hybrid transformer — best all-round choice |
| `htdemucs_ft` | Fine-tuned version — higher quality, slower |
| `htdemucs_6s` | 6-stem model — adds Guitar and Piano |
| `hdemucs_mmi` | Hybrid Demucs trained on extra data |
| `mdx` | MDX-Net competition model |
| `mdx_extra` | MDX-Net with extra training data |
| `mdx_q` | Quantized MDX — fastest |
| `mdx_extra_q` | Quantized MDX extra — best speed/quality tradeoff |

**GPU / CPU toggle**
Automatically detects your NVIDIA GPU via `nvidia-smi`. Switch between CUDA and CPU processing with one click. GPU processing is 10–40× faster on modern NVIDIA cards.

**Live progress log**
A scrolling output panel shows every line demucs prints in real time — no more guessing if it's still running. The full log is also saved to `%TEMP%\demucs_gui.log`.

**Detailed error reporting**
If something goes wrong, the last 40 lines of output are surfaced in a dialog with a one-click option to open the full log in Notepad — no digging through terminals needed.

**Command preview**
The exact command that will be run is shown before you click Separate, so power users can verify flags at a glance.

---

## Installation

### Option A — Installer (recommended for end users)

Download `DemucsStudio_Setup.exe` from the [Releases](../../releases) page and run it.

The installer handles everything automatically:

| Step | What happens |
|---|---|
| 1 | Copies the app to `C:\Program Files\DemucsStudio\` |
| 2 | Installs **.NET 8 Desktop Runtime** if not already present |
| 3 | Detects your NVIDIA GPU |
| 4 | Lets you choose **GPU (CUDA ~2.5 GB)**, **CPU (~250 MB)**, or both |
| 5 | Downloads and installs **Python 3.10** silently |
| 6 | Creates a Python venv at `%USERPROFILE%\demucs_env` |
| 7 | Installs **PyTorch** (CUDA or CPU build per your choice) |
| 8 | Installs **demucs** and **ffmpeg** |
| 9 | Creates Start Menu and optional desktop shortcut |

> **Requires an internet connection during install.** Download size is ~250 MB for CPU or ~2.5 GB for CUDA.

---

### Option B — Build from source

**Prerequisites**
- [.NET 8 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/8.0)
- [Visual Studio 2022](https://visualstudio.microsoft.com/) with the **.NET desktop development** workload
- A Python venv at `%USERPROFILE%\demucs_env` with `demucs` installed  
  *(the installer sets this up for you, or see [Manual Python Setup](#manual-python-setup) below)*

**Clone and run**
```bash
git clone https://github.com/your-username/DemucsStudio.git
cd DemucsStudio
dotnet run
```

Or open `DemucsGUI.slnx` in Visual Studio and press **F5**.

---

## Manual Python Setup

If you prefer to set up the Python environment yourself rather than using the installer:

```powershell
# 1. Create a venv (Python 3.10 required)
python -m venv %USERPROFILE%\demucs_env

# 2. Activate it
%USERPROFILE%\demucs_env\Scripts\activate

# 3. Install PyTorch — pick ONE of the following:

# GPU (CUDA 12.1) — requires NVIDIA GTX 900+ / RTX
pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu121

# CPU only — works on any machine
pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu

# 4. Install demucs
pip install demucs

# 5. Install ffmpeg (required for non-WAV formats)
winget install Gyan.FFmpeg
```

> The app looks for `%USERPROFILE%\demucs_env\Scripts\python.exe`. If your venv is elsewhere, update `VenvCandidates` in `DemucsService.cs`.

---

## Switching Backends

To switch from CPU to GPU (or back) after installation, re-run the setup script from the install folder:

```powershell
# Switch to GPU (CUDA)
powershell -ExecutionPolicy Bypass -File "C:\Program Files\DemucsStudio\setup_env.ps1" -UseCuda $true

# Switch to CPU
powershell -ExecutionPolicy Bypass -File "C:\Program Files\DemucsStudio\setup_env.ps1" -UseCuda $false
```

---

## Supported Audio Formats

`.mp3` · `.wav` · `.flac` · `.ogg` · `.m4a` · `.aac`

---

## Project Structure

```
DemucsGUI/
├── App.xaml / App.xaml.cs          — WPF application entry point
├── MainWindow.xaml                 — UI layout and styles
├── MainWindow.xaml.cs              — UI logic and event handlers
├── DemucsService.cs                — All business logic: venv discovery,
│                                     GPU detection, process execution, logging
├── DemucsGUI.csproj                — Project file (.NET 8, WPF + WinForms)
└── installer/
    ├── DemucsStudio.iss            — Inno Setup installer script
    ├── setup_env.ps1               — Python/venv/PyTorch setup script
    └── redist/
        └── dotnet8-desktop-runtime-x64.exe   — bundled .NET runtime
```

---

## System Requirements

| | Minimum | Recommended |
|---|---|---|
| **OS** | Windows 10 (1809) | Windows 11 |
| **RAM** | 8 GB | 16 GB |
| **Disk** | 5 GB free | 10 GB free |
| **CPU** | Any x64 | Modern multi-core |
| **GPU** | — | NVIDIA GTX 900 series or newer |
| **.NET** | 8.0 Desktop Runtime | 8.0 Desktop Runtime |

---

## Building the Installer

See [`installer/BUILD.md`](installer/BUILD.md) for full instructions. The short version:

```powershell
# 1. Publish the app
dotnet publish -c Release -r win-x64 --self-contained false -o bin\publish

# 2. Place the .NET 8 Desktop Runtime installer at:
#    installer\redist\dotnet8-desktop-runtime-x64.exe

# 3. Compile with Inno Setup 6
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" DemucsStudio.iss
# Output: installer\Output\DemucsStudio_Setup.exe
```

---

## Acknowledgements

- **[Demucs](https://github.com/facebookresearch/demucs)** by Meta Research — the underlying separation model
- **[PyTorch](https://pytorch.org/)** — deep learning framework powering the inference
- **[FFmpeg](https://ffmpeg.org/)** — audio decoding and encoding

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

Demucs itself is licensed under the MIT License. PyTorch is licensed under the BSD License.
