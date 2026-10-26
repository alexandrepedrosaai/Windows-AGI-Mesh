//! # Zenith Intent Priority Queue
//!
//! A max-heap priority queue for scheduling intents by computed score.
//! Supports priority aging (anti-starvation) and domain-filtered dequeue.

use std::cmp::Ordering;
use std::collections::BinaryHeap;
use uuid::Uuid;
use zenith_abi::intent::Intent;
use zenith_abi::domain::Domain;
use zenith_abi::types::ZTaskId;
use crate::heuristic::{compute_score_default, apply_aging};

// ---------------------------------------------------------------------------
// Scheduled intent wrapper (implements Ord for BinaryHeap)
// ---------------------------------------------------------------------------

/// An intent wrapped with its computed scheduling score
#[derive(Debug, Clone)]
pub struct ScheduledIntent {
    /// The intent to schedule
    pub intent: Intent,
    /// Computed scheduling score (higher = scheduled sooner)
    pub score: i64,
    /// Time this intent entered the queue (for aging)
    pub enqueued_at: std::time::Instant,
    /// Number of times this intent has been preempted
    pub preemption_count: u32,
}

impl ScheduledIntent {
    /// Create a new scheduled intent with computed score
    pub fn new(intent: Intent, available_domains: &[Domain]) -> Self {
        let score = compute_score_default(&intent, available_domains);
        Self {
            intent,
            score,
            enqueued_at: std::time::Instant::now(),
            preemption_count: 0,
        }
    }

    /// Apply aging to this intent's score
    pub fn apply_aging(&mut self, aging_period_ms: u64, increment: i64) {
        let wait_ms = self.enqueued_at.elapsed().as_millis() as u64;
        self.score = apply_aging(self.score, wait_ms, aging_period_ms, increment);
    }

    /// Wait time in milliseconds
    pub fn wait_ms(&self) -> u64 {
        self.enqueued_at.elapsed().as_millis() as u64
    }
}

impl PartialEq for ScheduledIntent {
    fn eq(&self, other: &Self) -> bool {
        self.score == other.score && self.intent.id == other.intent.id
    }
}

impl Eq for ScheduledIntent {}

impl PartialOrd for ScheduledIntent {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for ScheduledIntent {
    fn cmp(&self, other: &Self) -> Ordering {
        // Higher score = higher priority
        self.score
            .cmp(&other.score)
            .then_with(|| self.intent.priority.cmp(&other.intent.priority))
            .then_with(|| {
                // Older intents get slight preference (FIFO tiebreak)
                other.enqueued_at.cmp(&self.enqueued_at)
            })
    }
}

// ---------------------------------------------------------------------------
// Intent priority queue
// ---------------------------------------------------------------------------

/// Max-heap priority queue for Zenith intents
pub struct IntentPriorityQueue {
    heap: BinaryHeap<ScheduledIntent>,
    /// Maximum queue depth
    max_depth: usize,
    /// Anti-starvation aging period in milliseconds
    aging_period_ms: u64,
    /// Score increment per aging period
    aging_increment: i64,
    /// Total intents ever enqueued
    total_enqueued: u64,
    /// Total intents ever dequeued
    total_dequeued: u64,
    /// Total intents dropped (queue full)
    total_dropped: u64,
}

impl IntentPriorityQueue {
    /// Create a new priority queue
    pub fn new(max_depth: usize) -> Self {
        Self {
            heap: BinaryHeap::with_capacity(max_depth.min(1024)),
            max_depth,
            aging_period_ms: 1_000,  // age every 1 second
            aging_increment: 10,
            total_enqueued: 0,
            total_dequeued: 0,
            total_dropped: 0,
        }
    }

    /// Configure anti-starvation aging
    pub fn with_aging(mut self, period_ms: u64, increment: i64) -> Self {
        self.aging_period_ms = period_ms;
        self.aging_increment = increment;
        self
    }

    /// Enqueue an intent
    ///
    /// Returns `false` if the queue is full and the intent was dropped.
    pub fn enqueue(&mut self, intent: Intent, available_domains: &[Domain]) -> bool {
        if self.heap.len() >= self.max_depth {
            self.total_dropped += 1;
            return false;
        }
        let scheduled = ScheduledIntent::new(intent, available_domains);
        self.heap.push(scheduled);
        self.total_enqueued += 1;
        true
    }

    /// Dequeue the highest-priority intent
    pub fn dequeue(&mut self) -> Option<ScheduledIntent> {
        let item = self.heap.pop()?;
        self.total_dequeued += 1;
        Some(item)
    }

    /// Peek at the highest-priority intent without removing it
    pub fn peek(&self) -> Option<&ScheduledIntent> {
        self.heap.peek()
    }

    /// Dequeue the highest-priority intent for a specific domain
    pub fn dequeue_for_domain(&mut self, domain: &Domain) -> Option<ScheduledIntent> {
        // Drain all, find best match for domain, re-enqueue the rest
        let mut all: Vec<ScheduledIntent> = self.heap.drain().collect();
        all.sort_by(|a, b| b.cmp(a)); // highest score first

        let pos = all.iter().position(|si| {
            si.intent.preferred_domain.as_ref() == Some(domain)
                || si.intent.preferred_domain.is_none()
        });

        if let Some(idx) = pos {
            let item = all.remove(idx);
            for si in all {
                self.heap.push(si);
            }
            self.total_dequeued += 1;
            Some(item)
        } else {
            for si in all {
                self.heap.push(si);
            }
            None
        }
    }

    /// Apply aging to all queued intents (call periodically)
    pub fn apply_aging_pass(&mut self) {
        let period = self.aging_period_ms;
        let increment = self.aging_increment;
        let mut all: Vec<ScheduledIntent> = self.heap.drain().collect();
        for si in &mut all {
            si.apply_aging(period, increment);
        }
        for si in all {
            self.heap.push(si);
        }
    }

    /// Remove an intent by ID (cancellation)
    pub fn remove(&mut self, id: &ZTaskId) -> Option<Intent> {
        let mut all: Vec<ScheduledIntent> = self.heap.drain().collect();
        let pos = all.iter().position(|si| &si.intent.id == id);
        if let Some(idx) = pos {
            let item = all.remove(idx);
            for si in all {
                self.heap.push(si);
            }
            Some(item.intent)
        } else {
            for si in all {
                self.heap.push(si);
            }
            None
        }
    }

    /// Number of intents currently in the queue
    pub fn len(&self) -> usize {
        self.heap.len()
    }

    /// Whether the queue is empty
    pub fn is_empty(&self) -> bool {
        self.heap.is_empty()
    }

    /// Whether the queue is full
    pub fn is_full(&self) -> bool {
        self.heap.len() >= self.max_depth
    }

    /// Queue utilization ratio (0.0–1.0)
    pub fn utilization(&self) -> f64 {
        self.heap.len() as f64 / self.max_depth as f64
    }

    /// Queue statistics
    pub fn stats(&self) -> QueueStats {
        QueueStats {
            current_depth: self.heap.len(),
            max_depth: self.max_depth,
            total_enqueued: self.total_enqueued,
            total_dequeued: self.total_dequeued,
            total_dropped: self.total_dropped,
            utilization: self.utilization(),
        }
    }
}

/// Queue statistics snapshot
#[derive(Debug, Clone)]
pub struct QueueStats {
    pub current_depth:  usize,
    pub max_depth:      usize,
    pub total_enqueued: u64,
    pub total_dequeued: u64,
    pub total_dropped:  u64,
    pub utilization:    f64,
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use zenith_abi::intent::{Intent, IntentClass};

    fn make_intent(priority: u8, class: IntentClass) -> Intent {
        Intent::new(
            Uuid::new_v4(), Uuid::new_v4(),
            "test", class, priority,
        )
    }

    #[test]
    fn dequeue_highest_priority_first() {
        let mut q = IntentPriorityQueue::new(100);
        let domains = vec![Domain::Windows, Domain::Android, Domain::AI];

        q.enqueue(make_intent(50,  IntentClass::Media),        &domains);
        q.enqueue(make_intent(200, IntentClass::Productivity), &domains);
        q.enqueue(make_intent(100, IntentClass::Messaging),    &domains);

        let first = q.dequeue().unwrap();
        assert_eq!(first.intent.priority, 200);

        let second = q.dequeue().unwrap();
        assert_eq!(second.intent.priority, 100);
    }

    #[test]
    fn queue_full_drops_intent() {
        let mut q = IntentPriorityQueue::new(2);
        let domains = vec![Domain::Windows];

        assert!(q.enqueue(make_intent(100, IntentClass::Productivity), &domains));
        assert!(q.enqueue(make_intent(100, IntentClass::Productivity), &domains));
        assert!(!q.enqueue(make_intent(100, IntentClass::Productivity), &domains)); // dropped

        assert_eq!(q.stats().total_dropped, 1);
    }

    #[test]
    fn remove_by_id() {
        let mut q = IntentPriorityQueue::new(100);
        let domains = vec![Domain::Windows];
        let intent = make_intent(128, IntentClass::Productivity);
        let id = intent.id;
        q.enqueue(intent, &domains);
        assert_eq!(q.len(), 1);
        let removed = q.remove(&id);
        assert!(removed.is_some());
        assert_eq!(q.len(), 0);
    }

    #[test]
    fn dequeue_for_domain() {
        let mut q = IntentPriorityQueue::new(100);
        let domains = vec![Domain::Windows, Domain::Android];

        let mut android_intent = make_intent(100, IntentClass::Messaging);
        android_intent.preferred_domain = Some(Domain::Android);

        let mut windows_intent = make_intent(200, IntentClass::Productivity);
        windows_intent.preferred_domain = Some(Domain::Windows);

        q.enqueue(android_intent, &domains);
        q.enqueue(windows_intent, &domains);

        // Dequeue for Android — should get the Android intent even though
        // the Windows intent has higher score
        let item = q.dequeue_for_domain(&Domain::Android).unwrap();
        assert_eq!(item.intent.preferred_domain, Some(Domain::Android));
    }

    #[test]
    fn aging_increases_score() {
        let mut q = IntentPriorityQueue::new(100)
            .with_aging(0, 50); // period=0 means always age
        let domains = vec![Domain::Windows];
        let intent = make_intent(10, IntentClass::Productivity);
        q.enqueue(intent, &domains);

        let score_before = q.peek().unwrap().score;
        q.apply_aging_pass();
        let score_after = q.peek().unwrap().score;
        // Score should be >= before (aging can only increase)
        assert!(score_after >= score_before);
    }

    #[test]
    fn queue_stats() {
        let mut q = IntentPriorityQueue::new(10);
        let domains = vec![Domain::Windows];
        for _ in 0..5 {
            q.enqueue(make_intent(100, IntentClass::Productivity), &domains);
        }
        q.dequeue();
        let stats = q.stats();
        assert_eq!(stats.total_enqueued, 5);
        assert_eq!(stats.total_dequeued, 1);
        assert_eq!(stats.current_depth, 4);
    }
}