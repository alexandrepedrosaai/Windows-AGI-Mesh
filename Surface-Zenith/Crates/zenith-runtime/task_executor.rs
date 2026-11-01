//! # Task Executor
//!
//! Executes ZenithTasks within a domain runtime.

use std::collections::HashMap;
use uuid::Uuid;
use zenith_abi::domain::Domain;
use zenith_abi::task::{ZenithTask, TaskState, HardwareResource};
use zenith_abi::types::ZTaskId;
use crate::error::RuntimeError;

/// Task execution result
#[derive(Debug, Clone)]
pub struct ExecutionResult {
    pub task_id:      ZTaskId,
    pub success:      bool,
    pub result:       Vec<u8>,
    pub duration_ms:  u32,
    pub energy_mj:    u32,
    pub error:        Option<String>,
}

/// The Task Executor — runs tasks within a domain
#[derive(Debug)]
pub struct TaskExecutor {
    domain:          Domain,
    running:         HashMap<ZTaskId, ZenithTask>,
    completed:       Vec<ExecutionResult>,
    total_executed:  u64,
    total_failed:    u64,
    avg_duration_ms: f64,
}

impl TaskExecutor {
    pub fn new(domain: Domain) -> Self {
        Self {
            domain,
            running:         HashMap::new(),
            completed:       Vec::new(),
            total_executed:  0,
            total_failed:    0,
            avg_duration_ms: 0.0,
        }
    }

    /// Execute a task
    pub fn execute(&mut self, mut task: ZenithTask) -> ExecutionResult {
        let start = std::time::Instant::now();
        task.start();
        self.running.insert(task.id, task.clone());

        // Simulate execution based on hardware resource
        let (result_data, success) = self.simulate_execution(&task);
        let duration_ms = start.elapsed().as_millis() as u32;
        let energy_mj   = self.estimate_energy(&task.hardware, duration_ms);

        // Update task state
        if let Some(t) = self.running.get_mut(&task.id) {
            if success {
                t.complete(result_data.clone());
            } else {
                t.fail(-1, "Simulated execution failure");
            }
        }
        self.running.remove(&task.id);

        // Update metrics
        self.total_executed += 1;
        if !success { self.total_failed += 1; }
        let alpha = 0.1f64;
        self.avg_duration_ms = alpha * duration_ms as f64 + (1.0 - alpha) * self.avg_duration_ms;

        let result = ExecutionResult {
            task_id:     task.id,
            success,
            result:      result_data,
            duration_ms,
            energy_mj,
            error:       if success { None } else { Some("execution failed".into()) },
        };

        self.completed.push(result.clone());
        if self.completed.len() > 10_000 {
            self.completed.drain(0..1000);
        }

        result
    }

    /// Simulate task execution
    fn simulate_execution(&self, task: &ZenithTask) -> (Vec<u8>, bool) {
        let result = format!(
            "{{\"domain\":\"{}\",\"task\":\"{}\",\"status\":\"completed\"}}",
            self.domain.name(),
            task.description
        ).into_bytes();
        (result, true)
    }

    /// Estimate energy consumption
    fn estimate_energy(&self, hardware: &HardwareResource, duration_ms: u32) -> u32 {
        let power_mw = match hardware {
            HardwareResource::Cpu { cores } => (*cores as u32) * 500,
            HardwareResource::Gpu { vram_mb } => vram_mb / 100 * 1000,
            HardwareResource::Npu { tops }   => tops / 10,
            HardwareResource::Qpu            => 5000,
            HardwareResource::Dsp            => 200,
            _                                => 100,
        };
        (power_mw * duration_ms) / 1000
    }

    /// Execute multiple tasks in parallel (simulated)
    pub fn execute_batch(&mut self, tasks: Vec<ZenithTask>) -> Vec<ExecutionResult> {
        tasks.into_iter().map(|t| self.execute(t)).collect()
    }

    /// Running task count
    pub fn running_count(&self) -> usize { self.running.len() }

    /// Total executed
    pub fn total_executed(&self) -> u64 { self.total_executed }

    /// Success rate
    pub fn success_rate(&self) -> f64 {
        if self.total_executed == 0 { return 1.0; }
        (self.total_executed - self.total_failed) as f64 / self.total_executed as f64
    }

    /// Average duration in milliseconds
    pub fn avg_duration_ms(&self) -> f64 { self.avg_duration_ms }

    /// Domain
    pub fn domain(&self) -> &Domain { &self.domain }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_task(domain: Domain) -> ZenithTask {
        ZenithTask::new(
            Uuid::new_v4(), Uuid::new_v4(), Uuid::new_v4(),
            "test task", domain, HardwareResource::Cpu { cores: 2 }, 128,
        )
    }

    #[test]
    fn executor_execute_task() {
        let mut executor = TaskExecutor::new(Domain::Windows);
        let task = make_task(Domain::Windows);
        let result = executor.execute(task);
        assert!(result.success);
        assert!(!result.result.is_empty());
        assert_eq!(executor.total_executed(), 1);
    }

    #[test]
    fn executor_batch() {
        let mut executor = TaskExecutor::new(Domain::AI);
        let tasks: Vec<ZenithTask> = (0..5).map(|_| make_task(Domain::AI)).collect();
        let results = executor.execute_batch(tasks);
        assert_eq!(results.len(), 5);
        assert_eq!(executor.total_executed(), 5);
        assert_eq!(executor.success_rate(), 1.0);
    }

    #[test]
    fn executor_energy_estimation() {
        let mut executor = TaskExecutor::new(Domain::Windows);
        let mut task = make_task(Domain::Windows);
        task.hardware = HardwareResource::Npu { tops: 300 };
        let result = executor.execute(task);
        assert!(result.energy_mj > 0);
    }
}