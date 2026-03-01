; =============================================================================
;  DemucsStudio  —  Inno Setup installer script
;  Includes a custom PyTorch backend selection page with GPU auto-detection.
; =============================================================================

#define AppName    "DemucsStudio"
#define AppVersion "1.0.0"
#define AppPublisher "DemucsGUI"
#define AppExeName "DemucsStudio.exe"
#define AppURL     ""

[Setup]
AppId                    = {{F3A2B1C4-8E7D-4F6A-9B3C-2D1E5F7A8B9C}
AppName                  = {#AppName}
AppVersion               = {#AppVersion}
AppPublisher             = {#AppPublisher}
AppPublisherURL          = {#AppURL}
AppSupportURL            = {#AppURL}
AppUpdatesURL            = {#AppURL}
DefaultDirName           = {autopf}\{#AppName}
DefaultGroupName         = {#AppName}
AllowNoIcons             = yes
OutputDir                = installer\Output
OutputBaseFilename       = DemucsStudio_Setup
Compression              = lzma2/ultra64
SolidCompression         = yes
LZMANumBlockThreads      = 4
WizardStyle              = modern
WizardSizePercent        = 120
PrivilegesRequired       = admin
PrivilegesRequiredOverridesAllowed = commandline
ArchitecturesInstallIn64BitMode = x64compatible
ArchitecturesAllowed     = x64compatible
MinVersion               = 10.0.17763
UninstallDisplayIcon     = {app}\{#AppExeName}
UninstallDisplayName     = {#AppName}
; SetupIconFile          = installer\assets\icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "bin\publish\*";                              DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "installer\setup_env.ps1";                    DestDir: "{app}"; Flags: ignoreversion
Source: "installer\redist\dotnet8-desktop-runtime-x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall; Check: not IsDotNet8Installed

[Icons]
Name: "{group}\{#AppName}";         Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall";          Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";   Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

; =============================================================================
;  [Code]
; =============================================================================

[Code]

// ── Global state ──────────────────────────────────────────────────────────────

var
  // Detected GPU name, empty string = no NVIDIA GPU found
  GDetectedGpuName: String;
  // The user's final choice: True = CUDA, False = CPU-only
  GUseCuda: Boolean;

  // Custom page handle
  BackendPage: TWizardPage;

  // Controls on that page
  LblDetection:   TLabel;   // "GPU detected: RTX 4090" or "No NVIDIA GPU detected"
  LblNote:        TLabel;   // "You can change this at any time by re-running setup_env.ps1"

  RbCuda:         TCheckBox;
  RbCpu:          TCheckBox;

  // Info panels (simulated with labels inside coloured group boxes)
  GrpCuda:        TPanel;
  GrpCpu:         TPanel;

  LblCudaTitle:   TLabel;
  LblCudaBody:    TLabel;
  LblCpuTitle:    TLabel;
  LblCpuBody:     TLabel;

// ── GPU detection helper ──────────────────────────────────────────────────────

function DetectGpu: String;
// Returns the first GPU name from nvidia-smi, or '' if none found.
var
  outFile: String;
  lines:   TArrayOfString;
  res:     Integer;
begin
  Result  := '';
  outFile := ExpandConstant('{tmp}') + '\gpu_detect.txt';
  Exec('cmd',
       '/c nvidia-smi --query-gpu=name --format=csv,noheader > "' + outFile + '" 2>nul',
       '', SW_HIDE, ewWaitUntilTerminated, res);
  if (res = 0) and LoadStringsFromFile(outFile, lines) then
    if GetArrayLength(lines) > 0 then
      Result := Trim(lines[0]);
end;

// ── .NET 8 check ─────────────────────────────────────────────────────────────

function IsDotNet8Installed: Boolean;
var
  runtimes: TArrayOfString;
  i, res:   Integer;
  outFile:  String;
begin
  Result  := False;
  outFile := ExpandConstant('{tmp}') + '\dotnet_runtimes.txt';
  Exec('cmd',
       '/c dotnet --list-runtimes > "' + outFile + '" 2>nul',
       '', SW_HIDE, ewWaitUntilTerminated, res);
  if LoadStringsFromFile(outFile, runtimes) then
    for i := 0 to GetArrayLength(runtimes) - 1 do
      if Pos('Microsoft.WindowsDesktop.App 8.', runtimes[i]) > 0 then
      begin
        Result := True;
        Break;
      end;
end;

// ── Custom page construction ──────────────────────────────────────────────────

procedure RbClick(Sender: TObject);
begin
  // Highlight the selected panel, grey out the other
  if RbCuda.Checked then
  begin
    GrpCuda.Color := $001C3A00;   // dark teal-green tint
    GrpCpu.Color  := $00252525;
  end else
  begin
    GrpCpu.Color  := $00001C3A;   // dark blue tint
    GrpCuda.Color := $00252525;
  end;
end;

procedure CreateBackendPage;
var
  yPos: Integer;
begin
  BackendPage := CreateCustomPage(
    wpSelectTasks,
    'PyTorch Backend',
    'Choose how DemucsStudio will process audio on this computer.'
  );

  // ── Detection banner ──────────────────────────────────────────────────────

  LblDetection            := TLabel.Create(BackendPage);
  LblDetection.Parent     := BackendPage.Surface;
  LblDetection.Left       := 0;
  LblDetection.Top        := 0;
  LblDetection.Width      := BackendPage.SurfaceWidth;
  LblDetection.AutoSize   := False;
  LblDetection.Height     := 20;
  LblDetection.Font.Style := [fsBold];

  if GDetectedGpuName <> '' then
  begin
    LblDetection.Caption    := 'NVIDIA GPU detected:  ' + GDetectedGpuName;
    LblDetection.Font.Color := $0078C850;   // teal-green
  end else
  begin
    LblDetection.Caption    := 'No NVIDIA GPU detected on this machine.';
    LblDetection.Font.Color := $007090A0;   // grey-blue
  end;

  yPos := 28;

  // ── CUDA option panel ─────────────────────────────────────────────────────

  GrpCuda            := TPanel.Create(BackendPage);
  GrpCuda.Parent     := BackendPage.Surface;
  GrpCuda.Left       := 0;
  GrpCuda.Top        := yPos;
  GrpCuda.Width      := BackendPage.SurfaceWidth;
  GrpCuda.Height     := 88;
  GrpCuda.BevelOuter := bvNone;
  GrpCuda.Color      := $00252525;

  RbCuda              := TCheckBox.Create(BackendPage);
  RbCuda.Parent       := BackendPage.Surface;
  RbCuda.Left         := 10;
  RbCuda.Top          := 38;
  RbCuda.Width        := BackendPage.SurfaceWidth - 20;
  RbCuda.Height       := 18;
  RbCuda.Caption      := 'GPU  —  CUDA  (NVIDIA only)';
  RbCuda.Font.Style   := [fsBold];
  RbCuda.OnClick      := @RbClick;
  RbCuda.BringToFront;

  LblCudaBody             := TLabel.Create(BackendPage);
  LblCudaBody.Parent      := GrpCuda;
  LblCudaBody.Left        := 26;
  LblCudaBody.Top         := 32;
  LblCudaBody.Width       := GrpCuda.Width - 36;
  LblCudaBody.Height      := 50;
  LblCudaBody.AutoSize    := False;
  LblCudaBody.WordWrap    := True;
  LblCudaBody.Caption     :=
    'Download size:  ~2.5 GB   (PyTorch CUDA 12.1 build)'  + #13#10 +
    'Processing:     10–40× faster than CPU on modern GPUs' + #13#10 +
    'Requirement:    NVIDIA GPU with CUDA support (GTX 900+ / RTX series)';

  // ── CPU option panel ──────────────────────────────────────────────────────

  yPos := yPos + 96;

  GrpCpu            := TPanel.Create(BackendPage);
  GrpCpu.Parent     := BackendPage.Surface;
  GrpCpu.Left       := 0;
  GrpCpu.Top        := yPos;
  GrpCpu.Width      := BackendPage.SurfaceWidth;
  GrpCpu.Height     := 88;
  GrpCpu.BevelOuter := bvNone;
  GrpCpu.Color      := $00252525;

  RbCpu              := TCheckBox.Create(BackendPage);
  RbCpu.Parent       := BackendPage.Surface;
  RbCpu.Left         := 10;
  RbCpu.Top          := 134;
  RbCpu.Width        := BackendPage.SurfaceWidth - 20;
  RbCpu.Height       := 18;
  RbCpu.Caption      := 'CPU  —  Universal  (any machine)';
  RbCpu.Font.Style   := [fsBold];
  RbCpu.OnClick      := @RbClick;
  RbCpu.BringToFront;

  LblCpuBody             := TLabel.Create(BackendPage);
  LblCpuBody.Parent      := GrpCpu;
  LblCpuBody.Left        := 26;
  LblCpuBody.Top         := 32;
  LblCpuBody.Width       := GrpCpu.Width - 36;
  LblCpuBody.Height      := 50;
  LblCpuBody.AutoSize    := False;
  LblCpuBody.WordWrap    := True;
  LblCpuBody.Caption     :=
    'Download size:  ~250 MB   (PyTorch CPU build)'               + #13#10 +
    'Processing:     Slower — a 4-min song takes ~10–30 minutes'  + #13#10 +
    'Requirement:    None — works on any Windows 10/11 machine';

  // ── Footer note ───────────────────────────────────────────────────────────

  yPos := yPos + 96;

  LblNote             := TLabel.Create(BackendPage);
  LblNote.Parent      := BackendPage.Surface;
  LblNote.Left        := 0;
  LblNote.Top         := yPos;
  LblNote.Width       := BackendPage.SurfaceWidth;
  LblNote.AutoSize    := False;
  LblNote.Height      := 30;
  LblNote.WordWrap    := True;
  LblNote.Font.Color  := $009090A0;
  LblNote.Caption     := 'You can switch backends later by re-running  setup_env.ps1  from the install folder.';

  // ── Auto-select based on detection ────────────────────────────────────────

  if GDetectedGpuName <> '' then
  begin
    RbCuda.Checked  := True;
    RbCpu.Checked   := False;
  end else
  begin
    RbCuda.Checked  := False;
    RbCpu.Checked   := True;
    RbCuda.Enabled  := False;   // grey it out — no GPU present
  end;

  // Trigger colour update for initial state
  RbClick(nil);
end;

// ── Inno lifecycle hooks ─────────────────────────────────────────────────────

procedure InitializeWizard;
begin
  GDetectedGpuName := DetectGpu;
  GUseCuda         := (GDetectedGpuName <> '');
  CreateBackendPage;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  // Capture the user's choice when they leave the backend page
  if CurPageID = BackendPage.ID then
    GUseCuda := RbCuda.Checked;
end;

// ── .NET 8 install + env setup (runs after files are copied) ─────────────────

procedure CurStepChanged(CurStep: TSetupStep);
var
  res:      Integer;
  logPath:  String;
  psScript: String;
  cudaFlag: String;
begin
  if CurStep = ssPostInstall then
  begin
    logPath  := ExpandConstant('{tmp}') + '\demucs_setup.log';
    psScript := ExpandConstant('{app}') + '\setup_env.ps1';

    // ── .NET 8 runtime ───────────────────────────────────────────────────────
    if not IsDotNet8Installed then
    begin
      MsgBox('Installing .NET 8 Desktop Runtime. This may take a moment.',
             mbInformation, MB_OK);
      Exec(ExpandConstant('{tmp}') + '\dotnet8-desktop-runtime-x64.exe',
           '/install /quiet /norestart', '', SW_SHOW, ewWaitUntilTerminated, res);
      if res <> 0 then
        MsgBox('Warning: .NET 8 installation returned code ' + IntToStr(res) +
               '. The app may not run correctly.', mbError, MB_OK);
    end;

    // ── Execution policy ─────────────────────────────────────────────────────
    Exec('powershell',
         '-NoProfile -Command "Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force"',
         '', SW_HIDE, ewWaitUntilTerminated, res);

    // ── Build the -UseCuda flag to pass to PowerShell ─────────────────────────
    if GUseCuda then
      cudaFlag := '-UseCuda $true'
    else
      cudaFlag := '-UseCuda $false';

    // ── Confirm with user before the big download ─────────────────────────────
    if GUseCuda then
      MsgBox(
        'Ready to set up the Python environment.' + #13#10#13#10 +
        'Selected backend:  GPU (CUDA)' + #13#10 +
        'Download size:     ~2.5 GB' + #13#10#13#10 +
        'A terminal window will open showing progress.' + #13#10 +
        'Please leave it running until it closes.',
        mbInformation, MB_OK)
    else
      MsgBox(
        'Ready to set up the Python environment.' + #13#10#13#10 +
        'Selected backend:  CPU-only' + #13#10 +
        'Download size:     ~250 MB' + #13#10#13#10 +
        'A terminal window will open showing progress.' + #13#10 +
        'Please leave it running until it closes.',
        mbInformation, MB_OK);

    // ── Run the setup script with the user's choice ───────────────────────────
    Exec('powershell',
         '-NoProfile -ExecutionPolicy Bypass -File "' + psScript + '" ' +
         cudaFlag + ' -LogFile "' + logPath + '"',
         '', SW_SHOW, ewWaitUntilTerminated, res);

    if res <> 0 then
      MsgBox(
        'Python environment setup failed (exit code ' + IntToStr(res) + ').' + #13#10 +
        'Check the log at: ' + logPath + #13#10#13#10 +
        'You can re-run setup manually from:' + #13#10 +
        ExpandConstant('{app}') + '\setup_env.ps1',
        mbError, MB_OK)
    else
      MsgBox('Setup complete! DemucsStudio is ready to use.', mbInformation, MB_OK);
  end;
end;

// ── Uninstaller: offer to remove the venv ────────────────────────────────────

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  venvDir: String;
  res:     Integer;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    venvDir := ExpandConstant('{userprofile}') + '\demucs_env';
    if DirExists(venvDir) then
    begin
      res := MsgBox(
        'Remove the Python/demucs virtual environment?' + #13#10 +
        venvDir + #13#10#13#10 +
        'Yes  →  frees ~3–4 GB of disk space' + #13#10 +
        'No   →  keeps the environment (useful if you plan to reinstall)',
        mbConfirmation, MB_YESNO);
      if res = IDYES then
        DelTree(venvDir, True, True, True);
    end;
  end;
end;

