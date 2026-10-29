// =============================================================================
// Windows AGI Benchmark Lab — Rust Cross-Architecture Benchmark
// Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
// =============================================================================
//
// Portable Rust benchmark targeting:
//   - x86_64 (native, AVX2/AVX-512)
//   - aarch64 (ARM64, NEON)
//   - riscv64gc (RISC-V 64-bit)
//   - wasm32 (WebAssembly)
//
// Build:
//   Native:   cargo build --release
//   ARM64:    cargo build --release --target aarch64-unknown-linux-gnu
//   RISC-V:   cargo build --release --target riscv64gc-unknown-linux-gnu
//   WASM:     cargo build --release --target wasm32-unknown-unknown
// =============================================================================

use std::time::{Duration, Instant};
use std::fmt;

use clap::Parser;
use serde::{Deserialize, Serialize};

// ---------------------------------------------------------------------------
// CLI Arguments
// ---------------------------------------------------------------------------

#[derive(Parser, Debug)]
#[command(
    name = "agi-bench-rs",
    about = "Windows AGI Benchmark Lab — Rust Benchmark",
    version = "1.0.0",
    author = "Microsoft Corporation"
)]
struct Args {
    /// Benchmark suites to run
    #[arg(short, long, default_value = "all")]
    suite: String,

    /// Number of iterations multiplier
    #[arg(short, long, default_value_t = 1)]
    multiplier: u64,

    /// Output format (text, json)
    #[arg(short, long, default_value = "text")]
    output: String,

    /// Output file path
    #[arg(short, long)]
    file: Option<String>,

    /// Enable verbose output
    #[arg(short, long)]
    verbose: bool,

    /// Number of threads (0 = auto)
    #[arg(short, long, default_value_t = 0)]
    threads: usize,
}

// ---------------------------------------------------------------------------
// Result Types
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BenchResult {
    pub name: String,
    pub suite: String,
    pub iterations: u64,
    pub elapsed_sec: f64,
    pub metric: f64,
    pub unit: String,
    pub throughput: f64,
    pub arch: String,
    pub os: String,
    pub threads: usize,
    pub notes: String,
}

impl BenchResult {
    pub fn new(
        name: impl Into<String>,
        suite: impl Into<String>,
        iterations: u64,
        elapsed: Duration,
        metric: f64,
        unit: impl Into<String>,
    ) -> Self {
        Self {
            name: name.into(),
            suite: suite.into(),
            iterations,
            elapsed_sec: elapsed.as_secs_f64(),
            metric,
            unit: unit.into(),
            throughput: iterations as f64 / elapsed.as_secs_f64(),
            arch: std::env::consts::ARCH.to_string(),
            os: std::env::consts::OS.to_string(),
            threads: rayon::current_num_threads(),
            notes: String::new(),
        }
    }
}

impl fmt::Display for BenchResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "  {:<40} {:>10.3} {:<12}  ({:.3}s, {} iters)",
            self.name, self.metric, self.unit, self.elapsed_sec, self.iterations
        )
    }
}

// ---------------------------------------------------------------------------
// Benchmark: Integer Arithmetic
// ---------------------------------------------------------------------------

pub fn bench_integer_arithmetic(multiplier: u64) -> BenchResult {
    let iters = 10_000_000u64 * multiplier;
    let mut acc: u64 = 0x123456789ABCDEF0;
    let mul: u64 = 0xDEADBEEFCAFEBABE;
    let add: u64 = 0x0123456789ABCDEF;

    let t0 = Instant::now();

    for i in 0..iters {
        acc = acc.wrapping_mul(mul).wrapping_add(add);
        acc ^= acc >> 17;
        acc ^= acc << 31;
        acc ^= acc >> 43;
        acc = acc.wrapping_add(i);
    }

    let elapsed = t0.elapsed();

    // Prevent optimization
    if acc == 0 {
        eprintln!("(never)");
    }

    let mops = (iters * 7) as f64 / elapsed.as_secs_f64() / 1e6;
    BenchResult::new("Integer multiply-add-xor-shift", "integer", iters, elapsed, mops, "MOPS")
}

// ---------------------------------------------------------------------------
// Benchmark: Floating Point (f64)
// ---------------------------------------------------------------------------

pub fn bench_float64(multiplier: u64) -> BenchResult {
    let n = 1024usize;
    let iters = 5_000_000u64 * multiplier / n as u64;

    let mut a: Vec<f64> = (0..n).map(|i| i as f64 * 0.001 + 1.0).collect();
    let mut b: Vec<f64> = (0..n).map(|i| i as f64 * 0.002 + 2.0).collect();
    let mut c: Vec<f64> = vec![0.0f64; n];

    let t0 = Instant::now();

    for _ in 0..iters {
        for i in 0..n {
            // FMA: c[i] = a[i] * b[i] + c[i]
            c[i] = a[i].mul_add(b[i], c[i]);
            a[i] = c[i].mul_add(0.5, b[i]);
            b[i] = a[i] + c[i] * 0.25;
        }
    }

    let elapsed = t0.elapsed();

    if c[0] == 0.0 && c[1] == 0.0 {
        eprintln!("(never)");
    }

    let total_flops = iters * n as u64 * 5;
    let gflops = total_flops as f64 / elapsed.as_secs_f64() / 1e9;
    BenchResult::new("FP64 FMA array", "float", iters * n as u64, elapsed, gflops, "GFLOPS")
}

// ---------------------------------------------------------------------------
// Benchmark: Matrix Multiplication (f32)
// ---------------------------------------------------------------------------

pub fn bench_matmul(n: usize, multiplier: u64) -> BenchResult {
    let mut a: Vec<f32> = (0..n * n).map(|i| (i % 100) as f32 * 0.01 + 0.1).collect();
    let mut b: Vec<f32> = (0..n * n).map(|i| (i % 100) as f32 * 0.02 + 0.2).collect();
    let mut c: Vec<f32> = vec![0.0f32; n * n];

    let t0 = Instant::now();

    // Naive matrix multiplication (compiler may auto-vectorize)
    for i in 0..n {
        for k in 0..n {
            let a_ik = a[i * n + k];
            for j in 0..n {
                c[i * n + j] += a_ik * b[k * n + j];
            }
        }
    }

    let elapsed = t0.elapsed();

    if c[0] == 0.0 && c[1] == 0.0 {
        eprintln!("(never)");
    }

    let flops = 2.0 * n as f64 * n as f64 * n as f64;
    let gflops = flops / elapsed.as_secs_f64() / 1e9;
    let name = format!("MatMul {}x{} (f32)", n, n);
    BenchResult::new(name, "matmul", (n * n) as u64, elapsed, gflops, "GFLOPS")
}

// ---------------------------------------------------------------------------
// Benchmark: Memory Bandwidth
// ---------------------------------------------------------------------------

pub fn bench_memory_bandwidth(size_mb: usize, multiplier: u64) -> BenchResult {
    let n = size_mb * 1024 * 1024 / std::mem::size_of::<f64>();
    let src: Vec<f64> = (0..n).map(|i| i as f64 * 0.001).collect();
    let mut dst: Vec<f64> = vec![0.0f64; n];
    let reps = 5u64 * multiplier;

    let t0 = Instant::now();

    for _ in 0..reps {
        dst.copy_from_slice(&src);
    }

    let elapsed = t0.elapsed();

    if dst[0] == 0.0 && dst[1] == 0.0 {
        eprintln!("(never)");
    }

    let bytes = reps as f64 * n as f64 * std::mem::size_of::<f64>() as f64 * 2.0;
    let gbs = bytes / elapsed.as_secs_f64() / 1e9;
    let name = format!("Memory copy {}MB", size_mb);
    BenchResult::new(name, "memory", reps * n as u64, elapsed, gbs, "GB/s")
}

// ---------------------------------------------------------------------------
// Benchmark: Memory Latency (pointer chasing)
// ---------------------------------------------------------------------------

pub fn bench_memory_latency(size_bytes: usize) -> BenchResult {
    use rand::seq::SliceRandom;
    use rand::SeedableRng;

    let n = size_bytes / std::mem::size_of::<usize>();
    let n = n.max(64);

    let mut indices: Vec<usize> = (0..n).collect();
    let mut rng = rand::rngs::SmallRng::seed_from_u64(42);
    indices.shuffle(&mut rng);

    // Build pointer chain
    let mut chain: Vec<usize> = vec![0usize; n];
    for i in 0..n {
        chain[indices[i]] = indices[(i + 1) % n];
    }

    let accesses = 1_000_000u64;
    let mut idx = 0usize;

    let t0 = Instant::now();

    for _ in 0..accesses {
        // SAFETY: idx is always a valid index in chain
        idx = unsafe { *chain.get_unchecked(idx) };
    }

    let elapsed = t0.elapsed();

    if idx == usize::MAX {
        eprintln!("(never)");
    }

    let latency_ns = elapsed.as_secs_f64() / accesses as f64 * 1e9;
    let size_kb = size_bytes / 1024;
    let name = format!("Memory latency {}KB", size_kb);
    BenchResult::new(name, "latency", accesses, elapsed, latency_ns, "ns")
}

// ---------------------------------------------------------------------------
// Benchmark: Parallel (Rayon)
// ---------------------------------------------------------------------------

pub fn bench_parallel_sum(multiplier: u64) -> BenchResult {
    use rayon::prelude::*;

    let n = 100_000_000usize * multiplier as usize;
    let data: Vec<f64> = (0..n).map(|i| i as f64 * 0.000001).collect();

    let t0 = Instant::now();

    let sum: f64 = data.par_iter().sum();

    let elapsed = t0.elapsed();

    if sum == 0.0 {
        eprintln!("(never)");
    }

    let gbs = n as f64 * std::mem::size_of::<f64>() as f64 / elapsed.as_secs_f64() / 1e9;
    BenchResult::new(
        format!("Parallel sum {}M f64 ({} threads)", n / 1_000_000, rayon::current_num_threads()),
        "parallel",
        n as u64,
        elapsed,
        gbs,
        "GB/s",
    )
}

// ---------------------------------------------------------------------------
// Benchmark: Sorting
// ---------------------------------------------------------------------------

pub fn bench_sort(multiplier: u64) -> BenchResult {
    use rand::SeedableRng;
    use rand::RngCore;

    let n = 1_000_000usize * multiplier as usize;
    let mut rng = rand::rngs::SmallRng::seed_from_u64(42);
    let mut data: Vec<u64> = (0..n).map(|_| rng.next_u64()).collect();

    let t0 = Instant::now();

    data.sort_unstable();

    let elapsed = t0.elapsed();

    let melems = n as f64 / elapsed.as_secs_f64() / 1e6;
    BenchResult::new(
        format!("sort_unstable {}M u64", n / 1_000_000),
        "sort",
        n as u64,
        elapsed,
        melems,
        "Melems/s",
    )
}

// ---------------------------------------------------------------------------
// Benchmark: Hash (FNV-1a)
// ---------------------------------------------------------------------------

pub fn bench_hash(multiplier: u64) -> BenchResult {
    let size = 1024 * 1024usize;
    let reps = 100u64 * multiplier;
    let data: Vec<u8> = (0..size).map(|i| ((i * 7 + 13) % 256) as u8).collect();

    let t0 = Instant::now();

    let mut hash: u64 = 0;
    for _ in 0..reps {
        hash ^= fnv1a_64(&data);
    }

    let elapsed = t0.elapsed();

    if hash == 0 {
        eprintln!("(never)");
    }

    let gbs = reps as f64 * size as f64 / elapsed.as_secs_f64() / 1e9;
    BenchResult::new("FNV-1a 64-bit 1MB", "hash", reps * size as u64, elapsed, gbs, "GB/s")
}

fn fnv1a_64(data: &[u8]) -> u64 {
    let mut hash: u64 = 14695981039346656037;
    for &byte in data {
        hash ^= byte as u64;
        hash = hash.wrapping_mul(1099511628211);
    }
    hash
}

// ---------------------------------------------------------------------------
// Benchmark: String Operations
// ---------------------------------------------------------------------------

pub fn bench_string_ops(multiplier: u64) -> BenchResult {
    let size = 1024 * 1024usize;
    let reps = 50u64 * multiplier;
    let src: Vec<u8> = (0..size).map(|i| (i % 256) as u8).collect();
    let mut dst: Vec<u8> = vec![0u8; size];

    let t0 = Instant::now();

    for _ in 0..reps {
        dst.copy_from_slice(&src);
        dst[..size / 2].fill(b'B');
        let _ = src.iter().filter(|&&b| b == b'A').count();
    }

    let elapsed = t0.elapsed();

    if dst[0] == 0 && dst[1] == 0 {
        eprintln!("(never)");
    }

    let gbs = reps as f64 * size as f64 * 3.0 / elapsed.as_secs_f64() / 1e9;
    BenchResult::new("copy/fill/count 1MB", "string", reps * size as u64, elapsed, gbs, "GB/s")
}

// ---------------------------------------------------------------------------
// Benchmark: Transcendental Functions
// ---------------------------------------------------------------------------

pub fn bench_transcendental(multiplier: u64) -> BenchResult {
    let iters = 1_000_000u64 * multiplier;
    let mut acc = 0.0f64;

    let t0 = Instant::now();

    for i in 1..=iters {
        let x = i as f64 * 0.000001;
        acc += x.sin() + x.cos() + x.sqrt() + (x + 1.0).ln() + (-x).exp();
    }

    let elapsed = t0.elapsed();

    if acc == 0.0 {
        eprintln!("(never)");
    }

    let mops = iters as f64 * 5.0 / elapsed.as_secs_f64() / 1e6;
    BenchResult::new("sin+cos+sqrt+ln+exp", "transcendental", iters, elapsed, mops, "MOPS")
}

// ---------------------------------------------------------------------------
// Benchmark: Atomic Operations
// ---------------------------------------------------------------------------

pub fn bench_atomic(multiplier: u64) -> BenchResult {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Arc;

    let iters = 1_000_000u64 * multiplier;
    let counter = Arc::new(AtomicU64::new(0));

    let t0 = Instant::now();

    for _ in 0..iters {
        counter.fetch_add(1, Ordering::Relaxed);
    }

    let elapsed = t0.elapsed();

    let mops = iters as f64 / elapsed.as_secs_f64() / 1e6;
    BenchResult::new("Atomic fetch_add (Relaxed)", "atomic", iters, elapsed, mops, "MOPS")
}

// ---------------------------------------------------------------------------
// Benchmark: Channel Throughput
// ---------------------------------------------------------------------------

pub fn bench_channel(multiplier: u64) -> BenchResult {
    use std::sync::mpsc;
    use std::thread;

    let iters = 1_000_000u64 * multiplier;
    let (tx, rx) = mpsc::channel::<u64>();

    let t0 = Instant::now();

    let sender = thread::spawn(move || {
        for i in 0..iters {
            tx.send(i).unwrap();
        }
    });

    let mut sum = 0u64;
    for _ in 0..iters {
        sum = sum.wrapping_add(rx.recv().unwrap());
    }

    sender.join().unwrap();
    let elapsed = t0.elapsed();

    if sum == 0 {
        eprintln!("(never)");
    }

    let mops = iters as f64 / elapsed.as_secs_f64() / 1e6;
    BenchResult::new("mpsc channel throughput", "concurrency", iters, elapsed, mops, "Mmsg/s")
}

// ---------------------------------------------------------------------------
// System Information
// ---------------------------------------------------------------------------

fn print_header() {
    println!("=================================================================");
    println!("  Windows AGI Benchmark Lab — Rust Benchmark");
    println!("  Microsoft Corporation — Exclusive License");
    println!("=================================================================");
    println!("  Architecture:  {}", std::env::consts::ARCH);
    println!("  OS:            {}", std::env::consts::OS);
    println!("  Rust version:  {}", env!("CARGO_PKG_VERSION"));
    println!("  Threads:       {}", rayon::current_num_threads());
    println!("=================================================================");
    println!();
}

fn print_section(name: &str) {
    println!("\n[ {} ]", name);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    // Configure thread pool
    if args.threads > 0 {
        rayon::ThreadPoolBuilder::new()
            .num_threads(args.threads)
            .build_global()?;
    }

    if args.output == "text" {
        print_header();
        println!("Running benchmarks (multiplier={})...", args.multiplier);
    }

    let mut results: Vec<BenchResult> = Vec::new();
    let m = args.multiplier;

    let run_all = args.suite == "all";

    // Integer
    if run_all || args.suite == "integer" {
        if args.output == "text" { print_section("Integer Arithmetic"); }
        let r = bench_integer_arithmetic(m);
        if args.output == "text" { println!("{}", r); }
        results.push(r);
    }

    // Float
    if run_all || args.suite == "float" {
        if args.output == "text" { print_section("Floating Point"); }
        let r = bench_float64(m);
        if args.output == "text" { println!("{}", r); }
        results.push(r);
    }

    // MatMul
    if run_all || args.suite == "matmul" {
        if args.output == "text" { print_section("Matrix Multiplication"); }
        for &n in &[128usize, 256, 512, 1024] {
            let r = bench_matmul(n, m);
            if args.output == "text" { println!("{}", r); }
            results.push(r);
        }
    }

    // Memory bandwidth
    if run_all || args.suite == "memory" {
        if args.output == "text" { print_section("Memory Bandwidth"); }
        for &size_mb in &[1usize, 4, 16, 64, 256] {
            let r = bench_memory_bandwidth(size_mb, m);
            if args.output == "text" { println!("{}", r); }
            results.push(r);
        }
    }

    // Memory latency
    if run_all || args.suite == "latency" {
        if args.output == "text" { print_section("Memory Latency"); }
        for &size in &[32 * 1024usize, 256 * 1024, 8 * 1024 * 1024, 256 * 1024 * 1024] {
            let r = bench_memory_latency(size);
            if args.output == "text" { println!("{}", r); }
            results.push(r);
        }
    }

    // Parallel
    if run_all || args.suite == "parallel" {
        if args.output == "text" { print_section("Parallel (Rayon)"); }
        let r = bench_parallel_sum(m);
        if args.output == "text" { println!("{}", r); }
        results.push(r);
    }

    // Sort
    if run_all || args.suite == "sort" {
        if args.output == "text" { print_section("Sorting"); }
        let r = bench_sort(m);
        if args.output == "text" { println!("{}", r); }
        results.push(r);
    }

    // Hash
    if run_all || args.suite == "hash" {
        if args.output == "text" { print_section("Hash"); }
        let r = bench_hash(m);
        if args.output == "text" { println!("{}", r); }
        results.push(r);
    }

    // String
    if run_all || args.suite == "string" {
        if args.output == "text" { print_section("String Operations"); }
        let r = bench_string_ops(m);
        if args.output == "text" { println!("{}", r); }
        results.push(r);
    }

    // Transcendental
    if run_all || args.suite == "transcendental" {
        if args.output == "text" { print_section("Transcendental Functions"); }
        let r = bench_transcendental(m);
        if args.output == "text" { println!("{}", r); }
        results.push(r);
    }

    // Atomic
    if run_all || args.suite == "atomic" {
        if args.output == "text" { print_section("Atomic Operations"); }
        let r = bench_atomic(m);
        if args.output == "text" { println!("{}", r); }
        results.push(r);
    }

    // Channel
    if run_all || args.suite == "channel" {
        if args.output == "text" { print_section("Channel Throughput"); }
        let r = bench_channel(m);
        if args.output == "text" { println!("{}", r); }
        results.push(r);
    }

    // Output
    if args.output == "json" {
        let json = serde_json::to_string_pretty(&results)?;
        if let Some(path) = &args.file {
            std::fs::write(path, &json)?;
            eprintln!("Results saved to: {}", path);
        } else {
            println!("{}", json);
        }
    } else {
        println!("\n=================================================================");
        println!("  Benchmark complete — {} results", results.len());
        println!("  Architecture: {}", std::env::consts::ARCH);
        println!("  Microsoft Corporation — Windows AGI Benchmark Lab");
        println!("=================================================================");

        if let Some(path) = &args.file {
            let json = serde_json::to_string_pretty(&results)?;
            std::fs::write(path, json)?;
            println!("  Results saved to: {}", path);
        }
    }

    Ok(())
}
