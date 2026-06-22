using System.Diagnostics;
using System.IO.Compression;
using System.Net.Http;
using System.Windows.Forms;

namespace AndreyVPNUpdater;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new UpdaterForm(UpdaterArgs.Parse(args)));
    }
}

internal sealed class UpdaterArgs
{
    public string AppDir { get; init; } = "";
    public string ExePath { get; init; } = "";
    public string ZipUrl { get; init; } = "";
    public int AppPid { get; init; }
    public string LogDir { get; init; } = "";

    public static UpdaterArgs Parse(string[] args)
    {
        var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (args[i].StartsWith("--", StringComparison.Ordinal))
            {
                dict[args[i]] = args[i + 1];
                i++;
            }
        }

        return new UpdaterArgs
        {
            AppDir = dict.GetValueOrDefault("--appDir") ?? "",
            ExePath = dict.GetValueOrDefault("--exePath") ?? "",
            ZipUrl = dict.GetValueOrDefault("--zipUrl") ?? "",
            AppPid = int.TryParse(dict.GetValueOrDefault("--appPid"), out var pid) ? pid : 0,
            LogDir = dict.GetValueOrDefault("--logDir") ?? "",
        };
    }
}

internal sealed class UpdaterForm : Form
{
    private const long MaxLogBytes = 5L * 1024L * 1024L;
    private const int LogBackupCount = 3;

    private readonly UpdaterArgs _args;
    private readonly Label _statusLabel;
    private readonly ProgressBar _progressBar;
    private readonly string _logDir;
    private readonly string _logPath;

    public UpdaterForm(UpdaterArgs args)
    {
        _args = args;
        _logDir = !string.IsNullOrWhiteSpace(args.LogDir)
            ? args.LogDir
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AndreyVPN");
        _logPath = Path.Combine(_logDir, "AndreyVPN-update.log");

        Text = "Обновление AndreyVPN";
        Width = 460;
        Height = 150;
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;

        _statusLabel = new Label
        {
            AutoSize = false,
            Left = 20,
            Top = 20,
            Width = 405,
            Height = 35,
            Text = "Подготовка обновления...",
        };
        _progressBar = new ProgressBar
        {
            Left = 20,
            Top = 65,
            Width = 405,
            Height = 22,
            Style = ProgressBarStyle.Marquee,
            MarqueeAnimationSpeed = 30,
        };

        Controls.Add(_statusLabel);
        Controls.Add(_progressBar);
        Shown += async (_, _) => await RunUpdateAsync();
    }

    private async Task RunUpdateAsync()
    {
        try
        {
            Directory.CreateDirectory(_logDir);
            Log("=== AndreyVPN external updater started ===");
            Log($"AppDir={_args.AppDir}");
            Log($"ExePath={_args.ExePath}");
            Log($"ZipUrl={_args.ZipUrl}");
            Log($"AppPid={_args.AppPid}");
            Log($"LogDir={_args.LogDir}");

            ValidateArgs();

            var workDir = Path.Combine(Path.GetTempPath(), "AndreyVPN_Update_" + Guid.NewGuid());
            var zipPath = Path.Combine(workDir, "AndreyVPN-update.zip");
            var extractDir = Path.Combine(workDir, "extract");
            Directory.CreateDirectory(workDir);
            Directory.CreateDirectory(extractDir);
            Log($"WorkDir={workDir}");

            SetStatus("Скачивание обновления...");
            await DownloadAsync(_args.ZipUrl, zipPath);
            Log($"Download completed: {zipPath}");

            SetStatus("Ожидание закрытия AndreyVPN...");
            await WaitForAppExitAsync(_args.AppPid);
            await Task.Delay(2000);

            SetStatus("Распаковка обновления...");
            ZipFile.ExtractToDirectory(zipPath, extractDir, overwriteFiles: true);
            var sourceDir = ResolveSourceDir(extractDir, workDir);
            Log($"SourceDir={sourceDir}");

            SetStatus("Замена файлов...");
            await CopyDirectoryAsync(sourceDir, _args.AppDir);

            var updatedExe = Path.Combine(_args.AppDir, "AndreyVPN.exe");
            if (!File.Exists(updatedExe))
            {
                throw new FileNotFoundException("Updated AndreyVPN.exe was not found", updatedExe);
            }

            SetStatus("Запуск AndreyVPN...");
            Log("Starting updated AndreyVPN...");
            Process.Start(new ProcessStartInfo
            {
                FileName = updatedExe,
                WorkingDirectory = _args.AppDir,
                UseShellExecute = true,
            });

            Log("=== Update completed successfully ===");
            SetStatus("Обновление завершено");
            await Task.Delay(800);
            Close();
        }
        catch (Exception ex)
        {
            Log("UPDATE FAILED: " + ex);
            _progressBar.Style = ProgressBarStyle.Blocks;
            _progressBar.MarqueeAnimationSpeed = 0;
            SetStatus("Ошибка обновления. Подробности записаны в лог.");
            MessageBox.Show(
                $"Не удалось обновить AndreyVPN.\n\nЛог: {_logPath}\n\nОшибка: {ex.Message}",
                "AndreyVPN Update",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            Close();
        }
    }

    private void ValidateArgs()
    {
        if (string.IsNullOrWhiteSpace(_args.AppDir)) throw new ArgumentException("appDir is empty");
        if (string.IsNullOrWhiteSpace(_args.ExePath)) throw new ArgumentException("exePath is empty");
        if (string.IsNullOrWhiteSpace(_args.ZipUrl)) throw new ArgumentException("zipUrl is empty");
        if (!Directory.Exists(_args.AppDir)) throw new DirectoryNotFoundException(_args.AppDir);
    }

    private async Task DownloadAsync(string url, string zipPath)
    {
        using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
        using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        await using var input = await response.Content.ReadAsStreamAsync();
        await using var output = File.Create(zipPath);
        await input.CopyToAsync(output);
    }

    private async Task WaitForAppExitAsync(int pid)
    {
        if (pid <= 0) return;
        try
        {
            var process = Process.GetProcessById(pid);
            var start = DateTime.UtcNow;
            while (!process.HasExited && DateTime.UtcNow - start < TimeSpan.FromSeconds(120))
            {
                await Task.Delay(500);
                process.Refresh();
            }
        }
        catch (ArgumentException)
        {
            // Process already exited.
        }
    }

    private string ResolveSourceDir(string extractDir, string workDir)
    {
        if (File.Exists(Path.Combine(extractDir, "AndreyVPN.exe"))) return extractDir;

        var innerZip = Directory.EnumerateFiles(extractDir, "*.zip", SearchOption.AllDirectories)
            .FirstOrDefault(path =>
            {
                var name = Path.GetFileName(path).ToLowerInvariant();
                return name.Contains("windows") && name.Contains("portable");
            });

        if (innerZip is not null)
        {
            Log($"Found nested portable zip: {innerZip}");
            var nestedExtractDir = Path.Combine(workDir, "nested_extract");
            Directory.CreateDirectory(nestedExtractDir);
            ZipFile.ExtractToDirectory(innerZip, nestedExtractDir, overwriteFiles: true);
            if (File.Exists(Path.Combine(nestedExtractDir, "AndreyVPN.exe"))) return nestedExtractDir;
            extractDir = nestedExtractDir;
        }

        var candidate = Directory.EnumerateDirectories(extractDir, "*", SearchOption.AllDirectories)
            .FirstOrDefault(dir => File.Exists(Path.Combine(dir, "AndreyVPN.exe")));

        if (candidate is not null) return candidate;
        throw new FileNotFoundException("AndreyVPN.exe was not found inside downloaded update archive.");
    }

    private async Task CopyDirectoryAsync(string sourceDir, string targetDir)
    {
        foreach (var directory in Directory.EnumerateDirectories(sourceDir, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(sourceDir, directory);
            Directory.CreateDirectory(Path.Combine(targetDir, relative));
        }

        foreach (var file in Directory.EnumerateFiles(sourceDir, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(sourceDir, file);
            var target = Path.Combine(targetDir, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);

            const int maxAttempts = 20;
            for (var attempt = 1; attempt <= maxAttempts; attempt++)
            {
                try
                {
                    File.Copy(file, target, overwrite: true);
                    break;
                }
                catch (IOException) when (attempt < maxAttempts)
                {
                    await Task.Delay(500);
                }
                catch (UnauthorizedAccessException) when (attempt < maxAttempts)
                {
                    await Task.Delay(500);
                }
            }
        }
    }

    private void SetStatus(string text)
    {
        if (InvokeRequired)
        {
            Invoke(() => SetStatus(text));
            return;
        }
        _statusLabel.Text = text;
        Log(text);
    }

    private void Log(string message)
    {
        try
        {
            Directory.CreateDirectory(_logDir);
            RotateLogIfNeeded();
            File.AppendAllText(_logPath, $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}{Environment.NewLine}");
        }
        catch
        {
            // Ignore logging failures.
        }
    }

    private void RotateLogIfNeeded()
    {
        if (!File.Exists(_logPath) || new FileInfo(_logPath).Length < MaxLogBytes) return;

        var oldest = $"{_logPath}.{LogBackupCount}";
        if (File.Exists(oldest)) File.Delete(oldest);

        for (var index = LogBackupCount - 1; index >= 1; index--)
        {
            var source = $"{_logPath}.{index}";
            if (!File.Exists(source)) continue;
            File.Move(source, $"{_logPath}.{index + 1}");
        }

        File.Move(_logPath, $"{_logPath}.1");
    }
}
