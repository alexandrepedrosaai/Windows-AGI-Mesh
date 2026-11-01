//! # Resource Monitor
//!
//! Monitors CPU, memory, and I/O usage for domain runtimes.

use std::collections::{HashMap, VecDeque};
use serde::{Deserialize, Serialize};
use zenith_abi::domain::Domain;

/// Resource sample
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceSample {
    pub timestamp_ms:    u64,
    pub cpu_pct:         f64,
    pub memory_mb:       u64,
    pub memory_pct:      f64,
    pub io_read_mbps:    f64,
    pub io_write_mbps:   f64,
    pub network_mbps:    f64,
    pub active_tasks:    u32,
    pub thread_count:    u32,
}

impl ResourceSample {
    pub fn new(cpu_pct: f64, memory_mb: u64, memory_limit_mb: u64) -> Self {
        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;
        Self {
            timestamp_ms:  now_ms,
            cpu_pct,
            memory_mb,
            memory_pct:    if memory_limit_mb > 0 { memory_mb as f64 / memory_limit_mb as f64 * 100.0 } else { 0.0 },
            io_read_mbps:  0.0,
            io_write_mbps: 0.0,
            network_mbps:  0.0,
            active_tasks:  0,
            thread_count:  0,
        }
    }
}

/// Resource alert
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResourceAlert {
    pub domain:    String,
    pub resource:  String,
    pub value:     f64,
    pub threshold: f64,
    pub severity:  AlertSeverity,
    pub timestamp: std::time::Instant,
}

/// Alert severity
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum AlertSeverity {
    Info,
    Warning,
    Critical,
}

/// Resource monitor for a domain
#[derive(Debug)]
pub struct ResourceMonitor {
    domain:          Domain,
    samples:         VecDeque<ResourceSample>,
    alerts:          Vec<ResourceAlert>,
    max_samples:     usize,
    cpu_threshold:   f64,
    memory_threshold: f64,
    memory_limit_mb: u64,
    total_samples:   u64,
    total_alerts:    u64,
}

impl ResourceMonitor {
    pub fn new(domain: Domain, memory_limit_mb: u64) -> Self {
        Self {
            domain,
            samples:          VecDeque::new(),
            alerts:           Vec::new(),
            max_samples:      300, // 5 minutes at 1Hz
            cpu_threshold:    85.0,
            memory_threshold: 90.0,
            memory_limit_mb,
            total_samples:    0,
            total_alerts:     0,
        }
    }

    /// Record a resource sample
    pub fn record(&mut self, cpu_pct: f64, memory_mb: u64) {
        let sample = ResourceSample::new(cpu_pct, memory_mb, self.memory_limit_mb);
        self.total_samples += 1;

        // Check thresholds
        if cpu_pct > self.cpu_threshold {
            self.raise_alert("cpu", cpu_pct, self.cpu_threshold,
                if cpu_pct > 95.0 { AlertSeverity::Critical } else { AlertSeverity::Warning });
        }
        if sample.memory_pct > self.memory_threshold {
            self.raise_alert("memory", sample.memory_pct, self.memory_threshold,
                if sample.memory_pct > 98.0 { AlertSeverity::Critical } else { AlertSeverity::Warning });
        }

        self.samples.push_back(sample);
        if self.samples.len() > self.max_samples {
            self.samples.pop_front();
        }
    }

    fn raise_alert(&mut self, resource: &str, value: f64, threshold: f64, severity: AlertSeverity) {
        self.total_alerts += 1;
        self.alerts.push(ResourceAlert {
            domain:    self.domain.name().to_string(),
            resource:  resource.to_string(),
            value,
            threshold,
            severity,
            timestamp: std::time::Instant::now(),
        });
        if self.alerts.len() > 1000 {
            self.alerts.drain(0..100);
        }
    }

    /// Average CPU usage over the last N samples
    pub fn avg_cpu_pct(&self, last_n: usize) -> f64 {
        let samples: Vec<f64> = self.samples.iter().rev().take(last_n).map(|s| s.cpu_pct).collect();
        if samples.is_empty() { return 0.0; }
        samples.iter().sum::<f64>() / samples.len() as f64
    }

    /// Peak CPU usage
    pub fn peak_cpu_pct(&self) -> f64 {
        self.samples.iter().map(|s| s.cpu_pct).fold(0.0f64, f64::max)
    }

    /// Current memory usage
    pub fn current_memory_mb(&self) -> u64 {
        self.samples.back().map(|s| s.memory_mb).unwrap_or(0)
    }

    /// Current CPU usage
    pub fn current_cpu_pct(&self) -> f64 {
        self.samples.back().map(|s| s.cpu_pct).unwrap_or(0.0)
    }

    /// Recent alerts
    pub fn recent_alerts(&self, count: usize) -> &[ResourceAlert] {
        let len = self.alerts.len();
        &self.alerts[len.saturating_sub(count)..]
    }

    /// Critical alert count
    pub fn critical_alert_count(&self) -> usize {
        self.alerts.iter().filter(|a| a.severity == AlertSeverity::Critical).count()
    }

    pub fn total_samples(&self) -> u64 { self.total_samples }
    pub fn total_alerts(&self) -> u64 { self.total_alerts }
    pub fn sample_count(&self) -> usize { self.samples.len() }
}

/// Multi-domain resource monitor
#[derive(Debug, Default)]
pub struct MultiDomainMonitor {
    monitors: HashMap<String, ResourceMonitor>,
}

impl MultiDomainMonitor {
    pub fn new() -> Self { Self::default() }

    pub fn add_domain(&mut self, domain: Domain, memory_limit_mb: u64) {
        let key = domain.name().to_string();
        self.monitors.insert(key, ResourceMonitor::new(domain, memory_limit_mb));
    }

    pub fn record(&mut self, domain: &Domain, cpu_pct: f64, memory_mb: u64) {
        if let Some(monitor) = self.monitors.get_mut(domain.name()) {
            monitor.record(cpu_pct, memory_mb);
        }
    }

    pub fn get(&self, domain: &Domain) -> Option<&ResourceMonitor> {
        self.monitors.get(domain.name())
    }

    pub fn total_alerts(&self) -> u64 {
        self.monitors.values().map(|m| m.total_alerts()).sum()
    }

    pub fn any_critical(&self) -> bool {
        self.monitors.values().any(|m| m.critical_alert_count() > 0)
    }

    pub fn build_zenith_standard() -> Self {
        let mut monitor = Self::new();
        monitor.add_domain(Domain::Android,  4 * 1024);
        monitor.add_domain(Domain::Windows,  8 * 1024);
        monitor.add_domain(Domain::AI,       16 * 1024);
        monitor.add_domain(Domain::Quantum,  2 * 1024);
        monitor.add_domain(Domain::RealTime, 1 * 1024);
        monitor.add_domain(Domain::Cloud,    2 * 1024);
        monitor
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resource_monitor_record() {
        let mut monitor = ResourceMonitor::new(Domain::Windows, 8192);
        monitor.record(45.0, 2048);
        monitor.record(60.0, 3000);
        assert_eq!(monitor.sample_count(), 2);
        assert!((monitor.avg_cpu_pct(2) - 52.5).abs() < 0.01);
        assert_eq!(monitor.current_memory_mb(), 3000);
    }

    #[test]
    fn resource_monitor_alerts() {
        let mut monitor = ResourceMonitor::new(Domain::AI, 8192);
        monitor.record(90.0, 1000); // Above 85% threshold
        assert!(monitor.total_alerts() > 0);
        assert!(!monitor.recent_alerts(10).is_empty());
    }

    #[test]
    fn resource_monitor_peak_cpu() {
        let mut monitor = ResourceMonitor::new(Domain::Android, 4096);
        monitor.record(30.0, 500);
        monitor.record(75.0, 600);
        monitor.record(50.0, 550);
        assert!((monitor.peak_cpu_pct() - 75.0).abs() < 0.01);
    }

    #[test]
    fn multi_domain_monitor() {
        let mut monitor = MultiDomainMonitor::build_zenith_standard();
        monitor.record(&Domain::Windows, 55.0, 4096);
        monitor.record(&Domain::Android, 30.0, 1024);
        let win = monitor.get(&Domain::Windows).unwrap();
        assert_eq!(win.current_cpu_pct(), 55.0);
    }

    #[test]
    fn multi_domain_critical_detection() {
        let mut monitor = MultiDomainMonitor::build_zenith_standard();
        monitor.record(&Domain::AI, 99.0, 15000); // Critical CPU
        assert!(monitor.any_critical());
    }
}