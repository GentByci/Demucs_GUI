using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

namespace DemucsGUI
{
    // Carries the full captured output on failure so the UI can display it
    public class DemucsException : Exception
    {
        public string FullLog { get; }
        public DemucsException(string message, string fullLog) : base(message)
            => FullLog = fullLog;
    }

    /// <summary>
    /// All Demucs business logic: venv discovery, CUDA detection, command building, execution.
    /// Runs demucs as: python.exe -m demucs [args]  (no demucs.exe required)
    /// </summary>
    public class DemucsService
    {
        // ── Venv / Python resolution ─────────────────────────────────────────

        private static readonly string[] VenvCandidates =
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "demucs_env"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "demucs_env"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),      "demucs_env"),
            @"C:\demucs_env",
        };

        public static (string PythonExe, string Scripts)? FindVenvPython()
        {
            foreach (string root in VenvCandidates)
            {
                string python = Path.Combine(root, "Scripts", "python.exe");
                string scripts = Path.Combine(root, "Scripts");
                if (File.Exists(python))
                    return (python, scripts);
            }
            return null;
        }

        public static string? DetectedVenvRoot()
        {
            foreach (string root in VenvCandidates)
                if (File.Exists(Path.Combine(root, "Scripts", "python.exe")))
                    return root;
            return null;
        }

        // ── CUDA / GPU detection ─────────────────────────────────────────────

        public record GpuInfo(bool Found, string DisplayName);

        public static GpuInfo DetectGpu()
        {
            try
            {
                var psi = new ProcessStartInfo("nvidia-smi", "--query-gpu=name --format=csv,noheader")
                {
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using var proc = Process.Start(psi);
                if (proc == null) return new GpuInfo(false, "");

                string output = proc.StandardOutput.ReadToEnd().Trim();
                proc.WaitForExit();

                if (!string.IsNullOrWhiteSpace(output))
                    return new GpuInfo(true, output.Split('\n')[0].Trim());
            }
            catch { }

            return new GpuInfo(false, "");
        }

        // ── Command building ─────────────────────────────────────────────────

        public static string BuildArguments(
            string inputFile,
            string outputFolder,
            string model,
            bool useGpu,
            bool fullSeparation,
            int segment = 7)
        {
            string device = useGpu ? "cuda" : "cpu";
            string stemFlag = fullSeparation ? "" : "--two-stems=vocals ";
            return $"-m demucs {stemFlag}-n {model} --device {device} --segment {segment} -o \"{outputFolder}\" \"{inputFile}\"".Trim();
        }

        public static string BuildCommandPreview(
            string inputFile,
            string outputFolder,
            string model,
            bool useGpu,
            bool fullSeparation,
            int segment = 7)
        {
            string inputArg = string.IsNullOrWhiteSpace(inputFile) ? "<input_file>" : $"\"{inputFile}\"";
            string outputArg = string.IsNullOrWhiteSpace(outputFolder) ? "<output_folder>" : $"\"{outputFolder}\"";
            string device = useGpu ? "cuda" : "cpu";
            string stemFlag = fullSeparation ? "" : "--two-stems=vocals ";
            return $"python -m demucs {stemFlag}-n {model} --device {device} --segment {segment} -o {outputArg} {inputArg}".Trim();
        }

        // ── Process execution ────────────────────────────────────────────────

        public record ProgressUpdate(int Percent, string StatusLine);

        /// <summary>Full log of the most recent run, written in real time.</summary>
        public static string LogPath { get; } =
            Path.Combine(Path.GetTempPath(), "demucs_gui.log");

        private Process? _currentProcess;

        /// <summary>
        /// Runs:  [venv]\Scripts\python.exe -m demucs [arguments]
        ///
        /// Every stdout + stderr line is:
        ///   • forwarded to onLogLine so the UI can show a live scrolling log
        ///   • written to <see cref="LogPath"/> so you can inspect it after the run
        ///
        /// On failure a <see cref="DemucsException"/> is thrown that carries the
        /// full captured output — no information is ever silently swallowed.
        /// </summary>
        public async Task RunAsync(
            string arguments,
            IProgress<ProgressUpdate> onProgress,
            Action<string> onLogLine)
        {
            var venv = FindVenvPython();
            if (venv == null)
                throw new FileNotFoundException(
                    "Could not find a demucs venv.\n\n" +
                    "Expected python.exe at one of:\n" +
                    string.Join("\n", VenvCandidates));

            var (pythonExe, scripts) = venv.Value;

            var psi = new ProcessStartInfo(pythonExe, arguments)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            string existingPath = psi.EnvironmentVariables["PATH"] ?? "";
            if (!existingPath.Contains(scripts))
                psi.EnvironmentVariables["PATH"] = scripts + ";" + existingPath;

            // Force Python stdout/stderr to UTF-8 so paths with emoji/non-Latin
            // chars (e.g. u2b50ufe0f) do not crash the cp1252 codec.
            psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
            psi.EnvironmentVariables["PYTHONUTF8"] = "1";
            psi.StandardOutputEncoding = System.Text.Encoding.UTF8;
            psi.StandardErrorEncoding = System.Text.Encoding.UTF8;

            _currentProcess = new Process { StartInfo = psi };

            // Accumulate every line for the error report
            var allLines = new List<string>();
            var linesLock = new object();

            using var logWriter = new StreamWriter(LogPath, append: false) { AutoFlush = true };
            logWriter.WriteLine($"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}]");
            logWriter.WriteLine($"EXE : {pythonExe}");
            logWriter.WriteLine($"ARGS: {arguments}");
            logWriter.WriteLine(new string('-', 80));

            void Ingest(string tag, string? data)
            {
                if (data == null) return;
                string tagged = $"[{tag}] {data}";
                lock (linesLock) allLines.Add(tagged);
                logWriter.WriteLine(tagged);
                onLogLine(tagged);          // → live UI log panel
            }

            // stderr carries demucs progress bars AND Python tracebacks
            _currentProcess.ErrorDataReceived += (_, ev) =>
            {
                Ingest("ERR", ev.Data);
                if (ev.Data == null) return;

                int pct = 0;
                var m = Regex.Match(ev.Data, @"(\d+)%");
                if (m.Success) int.TryParse(m.Groups[1].Value, out pct);
                onProgress.Report(new ProgressUpdate(pct, ev.Data));
            };

            // stdout can also carry tracebacks in some Python / demucs versions
            _currentProcess.OutputDataReceived += (_, ev) => Ingest("OUT", ev.Data);

            _currentProcess.Start();
            _currentProcess.BeginErrorReadLine();
            _currentProcess.BeginOutputReadLine();

            await Task.Run(() => _currentProcess.WaitForExit());

            logWriter.WriteLine(new string('-', 80));
            logWriter.WriteLine($"Exit code: {_currentProcess.ExitCode}");

            if (_currentProcess.ExitCode != 0)
            {
                string fullLog;
                lock (linesLock) fullLog = string.Join("\n", allLines);

                // Surface the last 40 lines in the exception message
                string tail;
                lock (linesLock) tail = string.Join("\n", allLines.TakeLast(40));

                throw new DemucsException(
                    $"demucs exited with code {_currentProcess.ExitCode}.\n\n{tail}",
                    fullLog);
            }
        }

        public void Cancel()
        {
            try { _currentProcess?.Kill(entireProcessTree: true); }
            catch { /* already exited */ }
        }
    }
}