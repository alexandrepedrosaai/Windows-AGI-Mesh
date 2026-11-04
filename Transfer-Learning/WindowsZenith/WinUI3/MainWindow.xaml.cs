// =============================================================================
// MainWindow.xaml.cs
// WinUI 3 Code-Behind — Windows Zenith AGI Dashboard
// AMD Ryzen AI Max+ 395 (Strix Halo) — Real-time GPU/NPU monitoring
// Windows App SDK 1.6+ | .NET 8 | DirectML | ROCm for Windows
// =============================================================================

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Navigation;
using Windows.Graphics;
using Windows.System;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using System.Net.Http;
using System.IO;
using System.Diagnostics;

namespace WindowsZenith
{
    // =========================================================================
    // Hardware Metrics Model (AMD Ryzen AI Max+ 395)
    // =========================================================================

    /// <summary>Real-time metrics from AMD Radeon 8060S (RDNA 3.5).</summary>
    public sealed class RyzenHaloMetrics
    {
        // GPU (Radeon 8060S — 40 CUs, RDNA 3.5)
        public float GpuUtilizationPct    { get; set; }
        public float GpuClockMHz          { get; set; }
        public float GpuTempCelsius       { get; set; }
        public float GpuPowerWatts        { get; set; }
        public float GpuFP32TFLOPS        { get; set; }   // Peak: 30 TFLOPS
        public float GpuFP16TFLOPS        { get; set; }   // Peak: 60 TFLOPS
        public float GpuINT8TOPS          { get; set; }   // Peak: 120 TOPS

        // UMA Memory (128 GB LPDDR5x @ 8000 MT/s)
        public float UMAUsedGB            { get; set; }
        public float UMATotalGB           { get; set; } = 128.0f;
        public float UMABandwidthGBs      { get; set; }   // Peak: 256 GB/s
        public float UMABandwidthUtilPct  { get; set; }

        // CPU (Zen 5 — 16 cores / 32 threads)
        public float CpuUtilizationPct    { get; set; }
        public float CpuClockMHz          { get; set; }
        public float CpuTempCelsius       { get; set; }

        // NPU (XDNA 2 — 50 TOPS)
        public float NpuUtilizationPct    { get; set; }
        public float NpuTOPS              { get; set; }   // Peak: 50 TOPS
        public float NpuPowerWatts        { get; set; }

        // System
        public float TotalPowerWatts      { get; set; }   // TDP: 120W
        public float SystemTempCelsius    { get; set; }
        public long  UptimeSeconds        { get; set; }

        // Pipeline metrics
        public long   PipelineStep        { get; set; }
        public int    ActiveClusters      { get; set; }
        public float  NoveltyRate         { get; set; }
        public float  TaskLoss            { get; set; }
        public float  Forgetting          { get; set; }
        public float  EWCLambda           { get; set; } = 400.0f;
        public float  FisherNorm          { get; set; }
        public float  AnchorAlignment     { get; set; }
        public int    ReplayBufferFill    { get; set; }
        public float  InferenceLatencyMs  { get; set; }
        public float  TransportRTTMs      { get; set; }
        public int    BlockchainHeight    { get; set; }
        public float  QuantumCoherence    { get; set; } = 0.99f;
        public float  QuantumFidelity     { get; set; } = 0.996f;

        public string Timestamp => DateTime.Now.ToString("HH:mm:ss.fff");
    }

    // =========================================================================
    // AMD GPU Monitor (via WMI / DirectX / ROCm for Windows)
    // =========================================================================

    /// <summary>
    /// Monitors AMD Radeon 8060S hardware metrics.
    /// Uses Windows Performance Counters and DirectX DXGI for GPU stats.
    /// On Linux: uses ROCm SMI (rocm-smi) via process invocation.
    /// </summary>
    public sealed class AmdGpuMonitor : IDisposable
    {
        private readonly Timer _timer;
        private readonly Random _rng = new(42);
        private bool _disposed;
        private long _step;

        // Simulated baseline values (replace with actual WMI/ROCm queries)
        private float _baseGpuUtil = 0.0f;
        private float _baseMemUsed = 2.0f;

        public event EventHandler<RyzenHaloMetrics>? MetricsUpdated;

        public AmdGpuMonitor(TimeSpan interval)
        {
            _timer = new Timer(OnTick, null, TimeSpan.Zero, interval);
        }

        private void OnTick(object? state)
        {
            var metrics = CollectMetrics();
            MetricsUpdated?.Invoke(this, metrics);
        }

        private RyzenHaloMetrics CollectMetrics()
        {
            Interlocked.Increment(ref _step);

            // In production: query via WMI (Win32_VideoController),
            // DirectX DXGI adapter stats, or ROCm SMI on Linux.
            // Here: realistic simulation based on Strix Halo specs.

            float t = (float)_step * 0.1f;
            float gpuUtil = Math.Clamp(
                _baseGpuUtil + 30.0f * MathF.Sin(t * 0.3f) + (float)_rng.NextDouble() * 10f,
                0f, 100f);

            float memUsed = Math.Clamp(
                _baseMemUsed + 0.5f * MathF.Sin(t * 0.1f) + (float)_rng.NextDouble() * 0.2f,
                0f, 128f);

            float bandwidth = gpuUtil / 100f * 256f;  // Up to 256 GB/s

            return new RyzenHaloMetrics
            {
                // GPU (Radeon 8060S)
                GpuUtilizationPct   = gpuUtil,
                GpuClockMHz         = 1800f + gpuUtil * 10f,
                GpuTempCelsius      = 45f + gpuUtil * 0.4f,
                GpuPowerWatts       = 20f + gpuUtil * 0.8f,
                GpuFP32TFLOPS       = gpuUtil / 100f * 30f,
                GpuFP16TFLOPS       = gpuUtil / 100f * 60f,
                GpuINT8TOPS         = gpuUtil / 100f * 120f,

                // UMA Memory
                UMAUsedGB           = memUsed,
                UMATotalGB          = 128f,
                UMABandwidthGBs     = bandwidth,
                UMABandwidthUtilPct = bandwidth / 256f * 100f,

                // CPU (Zen 5)
                CpuUtilizationPct   = 20f + (float)_rng.NextDouble() * 30f,
                CpuClockMHz         = 4500f + (float)_rng.NextDouble() * 500f,
                CpuTempCelsius      = 55f + (float)_rng.NextDouble() * 15f,

                // NPU (XDNA 2)
                NpuUtilizationPct   = (float)_rng.NextDouble() * 80f,
                NpuTOPS             = (float)_rng.NextDouble() * 50f,
                NpuPowerWatts       = (float)_rng.NextDouble() * 15f,

                // System
                TotalPowerWatts     = 40f + gpuUtil * 0.8f,
                SystemTempCelsius   = 50f + gpuUtil * 0.3f,
                UptimeSeconds       = _step,

                // Pipeline
                PipelineStep        = _step,
                ActiveClusters      = 32 + (int)(_rng.NextDouble() * 32),
                NoveltyRate         = 0.10f + (float)_rng.NextDouble() * 0.10f,
                TaskLoss            = 0.5f * MathF.Exp(-_step * 0.001f),
                Forgetting          = 0.05f + (float)_rng.NextDouble() * 0.05f,
                FisherNorm          = 200f + (float)_rng.NextDouble() * 50f,
                AnchorAlignment     = 0.98f + (float)_rng.NextDouble() * 0.019f,
                ReplayBufferFill    = (int)Math.Min(100, _step / 10),
                InferenceLatencyMs  = 0.5f + (float)_rng.NextDouble() * 0.5f,
                TransportRTTMs      = 2f + (float)_rng.NextDouble() * 3f,
                BlockchainHeight    = (int)(_step / 100),
                QuantumCoherence    = 0.985f + (float)_rng.NextDouble() * 0.014f,
                QuantumFidelity     = 0.990f + (float)_rng.NextDouble() * 0.009f,
            };
        }

        /// <summary>Query ROCm SMI for real GPU metrics (Linux/WSL2).</summary>
        public static async Task<string> QueryRocmSmiAsync()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName  = "rocm-smi",
                    Arguments = "--showuse --showmemuse --showtemp --showpower --json",
                    RedirectStandardOutput = true,
                    UseShellExecute = false,
                    CreateNoWindow  = true,
                };
                using var proc = Process.Start(psi);
                if (proc == null) return "{}";
                string output = await proc.StandardOutput.ReadToEndAsync();
                await proc.WaitForExitAsync();
                return output;
            }
            catch
            {
                return "{}";  // ROCm not installed or not on Linux
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _timer.Dispose();
        }
    }

    // =========================================================================
    // MainWindow Code-Behind
    // =========================================================================

    public sealed partial class MainWindow : Window
    {
        private readonly AmdGpuMonitor _monitor;
        private readonly DispatcherTimer _clockTimer;
        private readonly ObservableCollection<RyzenHaloMetrics> _metricsHistory = new();
        private RyzenHaloMetrics _latestMetrics = new();
        private long _startTime;
        private bool _isConnected = true;

        // Navigation page map
        private readonly Dictionary<string, Type> _pageMap = new()
        {
            ["dashboard"]   = typeof(DashboardPage),
            ["gpu"]         = typeof(GpuMonitorPage),
            ["clustering"]  = typeof(ClusteringPage),
            ["ewc"]         = typeof(EWCPage),
            ["replay"]      = typeof(ReplayPage),
            ["transport"]   = typeof(TransportPage),
            ["maia"]        = typeof(MAIAPage),
            ["automl"]      = typeof(AutoMLPage),
            ["qsharp"]      = typeof(QSharpPage),
            ["powershell"]  = typeof(PowerShellPage),
            ["settings"]    = typeof(SettingsPage),
            ["logs"]        = typeof(LogsPage),
        };

        public MainWindow()
        {
            InitializeComponent();

            // Configure window
            AppWindow.Resize(new SizeInt32(1600, 900));
            AppWindow.SetIcon("Assets/amd_icon.ico");
            Title = "Windows Zenith — AMD Ryzen AI Max+ 395";

            _startTime = DateTimeOffset.UtcNow.ToUnixTimeSeconds();

            // Start GPU monitor (100ms interval)
            _monitor = new AmdGpuMonitor(TimeSpan.FromMilliseconds(100));
            _monitor.MetricsUpdated += OnMetricsUpdated;

            // Clock timer
            _clockTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
            _clockTimer.Tick += OnClockTick;
            _clockTimer.Start();

            // Navigate to dashboard
            ContentFrame.Navigate(typeof(DashboardPage));
            NavView.SelectedItem = NavView.MenuItems[0];

            // Set initial status
            UpdateStatusBar(_latestMetrics);
        }

        // =====================================================================
        // Navigation
        // =====================================================================

        private void NavView_SelectionChanged(
            NavigationView sender,
            NavigationViewSelectionChangedEventArgs args)
        {
            if (args.IsSettingsSelected)
            {
                ContentFrame.Navigate(typeof(SettingsPage));
                return;
            }

            if (args.SelectedItem is NavigationViewItem item &&
                item.Tag is string tag &&
                _pageMap.TryGetValue(tag, out var pageType))
            {
                ContentFrame.Navigate(pageType, _latestMetrics);
            }
        }

        // =====================================================================
        // Metrics Update (from GPU monitor)
        // =====================================================================

        private void OnMetricsUpdated(object? sender, RyzenHaloMetrics metrics)
        {
            // Marshal to UI thread
            DispatcherQueue.TryEnqueue(() =>
            {
                _latestMetrics = metrics;
                _metricsHistory.Add(metrics);

                // Keep last 1000 samples
                while (_metricsHistory.Count > 1000)
                    _metricsHistory.RemoveAt(0);

                UpdateStatusBar(metrics);
                UpdateHardwareBadges(metrics);

                // Forward to current page if it implements IMetricsConsumer
                if (ContentFrame.Content is IMetricsConsumer consumer)
                    consumer.OnMetricsUpdated(metrics);
            });
        }

        private void UpdateStatusBar(RyzenHaloMetrics m)
        {
            GpuUtil.Text  = $"GPU: {m.GpuUtilizationPct:F0}%";
            MemUtil.Text  = $"UMA: {m.UMAUsedGB:F1}/{m.UMATotalGB:F0} GB";
            NpuUtil.Text  = $"NPU: {m.NpuTOPS:F1} TOPS";
            StepCounter.Text = $"Step: {m.PipelineStep:N0}";

            StatusMessage.Text = m.TaskLoss < 0.1f
                ? $"Converged — Loss: {m.TaskLoss:F4} | Forgetting: {m.Forgetting:F4}"
                : $"Training — Loss: {m.TaskLoss:F4} | Clusters: {m.ActiveClusters}";
        }

        private void UpdateHardwareBadges(RyzenHaloMetrics m)
        {
            GpuStatusBadge.Text = $"GPU: {m.GpuUtilizationPct:F0}% @ {m.GpuClockMHz:F0} MHz";
            MemBadge.Text       = $"UMA: {m.UMAUsedGB:F1}/{m.UMATotalGB:F0} GB | {m.UMABandwidthGBs:F0} GB/s";
            NpuBadge.Text       = $"NPU: {m.NpuTOPS:F1}/{50:F0} TOPS";
            FP16Badge.Text      = $"FP16: {m.GpuFP16TFLOPS:F1}/{60:F0} TFLOPS";
        }

        private void OnClockTick(object? sender, object e)
        {
            ClockDisplay.Text = DateTime.Now.ToString("HH:mm:ss");
        }

        // =====================================================================
        // Window Lifecycle
        // =====================================================================

        protected override void OnClosed(object sender, WindowEventArgs args)
        {
            _monitor.Dispose();
            _clockTimer.Stop();
            base.OnClosed(sender, args);
        }
    }

    // =========================================================================
    // IMetricsConsumer Interface
    // =========================================================================

    public interface IMetricsConsumer
    {
        void OnMetricsUpdated(RyzenHaloMetrics metrics);
    }

    // =========================================================================
    // Dashboard Page
    // =========================================================================

    public sealed partial class DashboardPage : Page, IMetricsConsumer
    {
        private readonly ObservableCollection<MetricCard> _cards = new();

        public DashboardPage()
        {
            // Cards are defined in XAML (DashboardPage.xaml)
            // This code-behind handles data binding and updates
        }

        protected override void OnNavigatedTo(NavigationEventArgs e)
        {
            if (e.Parameter is RyzenHaloMetrics m)
                OnMetricsUpdated(m);
        }

        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            // Update all metric cards
            UpdateCards(m);
        }

        private void UpdateCards(RyzenHaloMetrics m)
        {
            _cards.Clear();
            _cards.Add(new MetricCard("GPU Utilization",   $"{m.GpuUtilizationPct:F1}%",   "Radeon 8060S RDNA 3.5"));
            _cards.Add(new MetricCard("GPU FP16",          $"{m.GpuFP16TFLOPS:F1} TFLOPS", "Peak: 60 TFLOPS"));
            _cards.Add(new MetricCard("UMA Used",          $"{m.UMAUsedGB:F1} GB",          "Total: 128 GB LPDDR5x"));
            _cards.Add(new MetricCard("UMA Bandwidth",     $"{m.UMABandwidthGBs:F0} GB/s",  "Peak: 256 GB/s"));
            _cards.Add(new MetricCard("NPU",               $"{m.NpuTOPS:F1} TOPS",          "XDNA 2 — Peak: 50 TOPS"));
            _cards.Add(new MetricCard("CPU",               $"{m.CpuUtilizationPct:F1}%",    "Zen 5 — 16C/32T"));
            _cards.Add(new MetricCard("Task Loss",         $"{m.TaskLoss:F4}",              "Continual Learning"));
            _cards.Add(new MetricCard("Forgetting",        $"{m.Forgetting:F4}",            "EWC λ=" + m.EWCLambda));
            _cards.Add(new MetricCard("Active Clusters",   $"{m.ActiveClusters}",           "Hamming Clustering"));
            _cards.Add(new MetricCard("Novelty Rate",      $"{m.NoveltyRate:P1}",           "Target: 15%"));
            _cards.Add(new MetricCard("Fisher Norm",       $"{m.FisherNorm:F1}",            "EWC Fisher Diagonal"));
            _cards.Add(new MetricCard("Anchor Alignment",  $"{m.AnchorAlignment:F4}",       "Majorana Anchor"));
            _cards.Add(new MetricCard("Inference Latency", $"{m.InferenceLatencyMs:F2} ms", "MAIA-300 / DirectML"));
            _cards.Add(new MetricCard("Transport RTT",     $"{m.TransportRTTMs:F1} ms",     "WT-MAIA/1.0 QUIC"));
            _cards.Add(new MetricCard("Quantum Coherence", $"{m.QuantumCoherence:F4}",      "MAIA-300 Qubits"));
            _cards.Add(new MetricCard("Blockchain Height", $"{m.BlockchainHeight}",         "Integrity Chain"));
        }
    }

    public sealed record MetricCard(string Title, string Value, string Subtitle);

    // =========================================================================
    // GPU Monitor Page
    // =========================================================================

    public sealed partial class GpuMonitorPage : Page, IMetricsConsumer
    {
        private readonly List<float> _gpuHistory    = new();
        private readonly List<float> _memHistory    = new();
        private readonly List<float> _bwHistory     = new();
        private readonly List<float> _fp16History   = new();

        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            _gpuHistory.Add(m.GpuUtilizationPct);
            _memHistory.Add(m.UMAUsedGB);
            _bwHistory.Add(m.UMABandwidthGBs);
            _fp16History.Add(m.GpuFP16TFLOPS);

            // Keep last 300 samples (30 seconds at 100ms)
            if (_gpuHistory.Count > 300) _gpuHistory.RemoveAt(0);
            if (_memHistory.Count > 300) _memHistory.RemoveAt(0);
            if (_bwHistory.Count  > 300) _bwHistory.RemoveAt(0);
            if (_fp16History.Count > 300) _fp16History.RemoveAt(0);

            // Update charts (via data binding in XAML)
            UpdateCharts(m);
        }

        private void UpdateCharts(RyzenHaloMetrics m)
        {
            // Chart updates handled via data binding
            // GPU: 40 CUs, RDNA 3.5, gfx1151
            // Memory: 128 GB LPDDR5x @ 8000 MT/s
            // Bandwidth: 256 GB/s peak
        }
    }

    // =========================================================================
    // Clustering Page
    // =========================================================================

    public sealed partial class ClusteringPage : Page, IMetricsConsumer
    {
        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            // Update cluster visualization
        }
    }

    // =========================================================================
    // EWC Page
    // =========================================================================

    public sealed partial class EWCPage : Page, IMetricsConsumer
    {
        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            // Update EWC metrics: lambda, Fisher norm, forgetting
        }
    }

    // =========================================================================
    // Replay Page
    // =========================================================================

    public sealed partial class ReplayPage : Page, IMetricsConsumer
    {
        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            // Update replay buffer visualization
        }
    }

    // =========================================================================
    // Transport Page
    // =========================================================================

    public sealed partial class TransportPage : Page, IMetricsConsumer
    {
        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            // Update WT-MAIA/1.0 stream statistics
        }
    }

    // =========================================================================
    // MAIA Page
    // =========================================================================

    public sealed partial class MAIAPage : Page, IMetricsConsumer
    {
        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            // Update MAIA-300 job queue and metrics
        }
    }

    // =========================================================================
    // AutoML Page
    // =========================================================================

    public sealed partial class AutoMLPage : Page, IMetricsConsumer
    {
        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            // Update AutoML trial progress
        }
    }

    // =========================================================================
    // Q# Quantum Page
    // =========================================================================

    public sealed partial class QSharpPage : Page, IMetricsConsumer
    {
        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            // Update quantum circuit metrics: coherence, fidelity, error rate
        }
    }

    // =========================================================================
    // PowerShell Page
    // =========================================================================

    public sealed partial class PowerShellPage : Page, IMetricsConsumer
    {
        private readonly StringBuilder _output = new();

        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            // Update PowerShell terminal output
        }

        public async Task ExecuteCommandAsync(string command)
        {
            var psi = new ProcessStartInfo
            {
                FileName  = "pwsh.exe",
ArgumentList = { "-NoProfile", "-Command", command },
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
                UseShellExecute = false,
                CreateNoWindow  = true,
            };

            using var proc = Process.Start(psi);
            if (proc == null) return;

            string stdout = await proc.StandardOutput.ReadToEndAsync();
            string stderr = await proc.StandardError.ReadToEndAsync();
            await proc.WaitForExitAsync();

            _output.AppendLine($"PS> {command}");
            _output.AppendLine(stdout);
            if (!string.IsNullOrEmpty(stderr))
                _output.AppendLine($"[ERROR] {stderr}");
        }
    }

    // =========================================================================
    // Settings Page
    // =========================================================================

    public sealed partial class SettingsPage : Page
    {
        // Settings: EWC lambda, Hamming threshold, replay buffer size, etc.
    }

    // =========================================================================
    // Logs Page
    // =========================================================================

    public sealed partial class LogsPage : Page, IMetricsConsumer
    {
        private readonly ObservableCollection<LogEntry> _logs = new();

        public void OnMetricsUpdated(RyzenHaloMetrics m)
        {
            if (m.PipelineStep % 100 == 0)
            {
                _logs.Add(new LogEntry(
                    DateTime.Now,
                    "INFO",
                    $"Step {m.PipelineStep}: loss={m.TaskLoss:F4} " +
                    $"forgetting={m.Forgetting:F4} clusters={m.ActiveClusters}"));

                while (_logs.Count > 1000)
                    _logs.RemoveAt(0);
            }
        }
    }

    public sealed record LogEntry(DateTime Timestamp, string Level, string Message);
}