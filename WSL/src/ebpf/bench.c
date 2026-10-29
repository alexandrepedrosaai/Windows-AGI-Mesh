// =============================================================================
// Windows AGI Benchmark Lab — eBPF Benchmark Program
// Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
// =============================================================================
// eBPF (extended Berkeley Packet Filter) benchmark
// Runs in Linux kernel space for ultra-low-latency measurements
//
// Build:
//   clang -O2 -target bpf -c bench.c -o bench.o
//   bpftool prog load bench.o /sys/fs/bpf/agi_bench
//
// Requirements:
//   - Linux kernel >= 5.15
//   - clang >= 12
//   - libbpf
//   - bpftool
// =============================================================================

#include <linux/bpf.h>
#include <linux/ptrace.h>
#include <linux/types.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>

// ---------------------------------------------------------------------------
// License (required for eBPF programs)
// ---------------------------------------------------------------------------
char LICENSE[] SEC("license") = "GPL";

// ---------------------------------------------------------------------------
// BPF Maps — shared memory between kernel and userspace
// ---------------------------------------------------------------------------

// Latency histogram (nanoseconds)
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 1024);
    __type(key, __u32);
    __type(value, __u64);
} latency_histogram SEC(".maps");

// Per-CPU counters
struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, 16);
    __type(key, __u32);
    __type(value, __u64);
} cpu_counters SEC(".maps");

// Ring buffer for events
struct {
    __uint(type, BPF_MAP_TYPE_RINGBUF);
    __uint(max_entries, 256 * 1024);  // 256 KB
} events SEC(".maps");

// Hash map for process tracking
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 10240);
    __type(key, __u32);   // PID
    __type(value, __u64); // start timestamp
} pid_start_times SEC(".maps");

// LRU hash for recent events
struct {
    __uint(type, BPF_MAP_TYPE_LRU_HASH);
    __uint(max_entries, 4096);
    __type(key, __u64);
    __type(value, __u64);
} recent_events SEC(".maps");

// ---------------------------------------------------------------------------
// Event Structures
// ---------------------------------------------------------------------------

struct syscall_event {
    __u64 timestamp_ns;
    __u64 duration_ns;
    __u32 pid;
    __u32 tid;
    __u32 syscall_nr;
    __u32 cpu_id;
    char comm[16];
};

struct memory_event {
    __u64 timestamp_ns;
    __u64 address;
    __u64 size;
    __u32 pid;
    __u32 flags;
};

struct inference_event {
    __u64 timestamp_ns;
    __u64 tokens_generated;
    __u64 latency_ns;
    __u32 pid;
    __u32 model_id;
};

// ---------------------------------------------------------------------------
// Counter Keys
// ---------------------------------------------------------------------------
#define COUNTER_SYSCALLS    0
#define COUNTER_READS       1
#define COUNTER_WRITES      2
#define COUNTER_MMAP        3
#define COUNTER_FAULTS      4
#define COUNTER_CONTEXT_SW  5
#define COUNTER_INTERRUPTS  6
#define COUNTER_INFERENCES  7

// ---------------------------------------------------------------------------
// Helper: Increment per-CPU counter
// ---------------------------------------------------------------------------
static __always_inline void increment_counter(__u32 key) {
    __u64 *val = bpf_map_lookup_elem(&cpu_counters, &key);
    if (val) {
        __sync_fetch_and_add(val, 1);
    }
}

// ---------------------------------------------------------------------------
// Helper: Record latency in histogram
// ---------------------------------------------------------------------------
static __always_inline void record_latency(__u64 latency_ns) {
    // Bucket: log2(latency_ns) clamped to [0, 1023]
    __u32 bucket = 0;
    __u64 val = latency_ns;

    if (val > 0) {
        // Simple log2 approximation
        while (val > 1 && bucket < 1023) {
            val >>= 1;
            bucket++;
        }
    }

    __u64 *count = bpf_map_lookup_elem(&latency_histogram, &bucket);
    if (count) {
        __sync_fetch_and_add(count, 1);
    }
}

// ---------------------------------------------------------------------------
// Tracepoint: sys_enter — Track syscall entry
// ---------------------------------------------------------------------------
SEC("tracepoint/raw_syscalls/sys_enter")
int trace_sys_enter(struct trace_event_raw_sys_enter *ctx) {
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 pid = pid_tgid >> 32;
    __u64 ts = bpf_ktime_get_ns();

    // Record start time for this PID
    bpf_map_update_elem(&pid_start_times, &pid, &ts, BPF_ANY);

    increment_counter(COUNTER_SYSCALLS);

    return 0;
}

// ---------------------------------------------------------------------------
// Tracepoint: sys_exit — Measure syscall latency
// ---------------------------------------------------------------------------
SEC("tracepoint/raw_syscalls/sys_exit")
int trace_sys_exit(struct trace_event_raw_sys_exit *ctx) {
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 pid = pid_tgid >> 32;
    __u32 tid = (__u32)pid_tgid;
    __u64 ts = bpf_ktime_get_ns();

    // Look up start time
    __u64 *start_ts = bpf_map_lookup_elem(&pid_start_times, &pid);
    if (!start_ts) {
        return 0;
    }

    __u64 duration_ns = ts - *start_ts;

    // Record in histogram
    record_latency(duration_ns);

    // Emit event to ring buffer for high-latency syscalls (> 1ms)
    if (duration_ns > 1000000) {
        struct syscall_event *event = bpf_ringbuf_reserve(&events, sizeof(*event), 0);
        if (event) {
            event->timestamp_ns = ts;
            event->duration_ns = duration_ns;
            event->pid = pid;
            event->tid = tid;
            event->syscall_nr = (__u32)ctx->id;
            event->cpu_id = bpf_get_smp_processor_id();
            bpf_get_current_comm(event->comm, sizeof(event->comm));
            bpf_ringbuf_submit(event, 0);
        }
    }

    // Clean up
    bpf_map_delete_elem(&pid_start_times, &pid);

    return 0;
}

// ---------------------------------------------------------------------------
// Kprobe: vfs_read — Track file read operations
// ---------------------------------------------------------------------------
SEC("kprobe/vfs_read")
int kprobe_vfs_read(struct pt_regs *ctx) {
    increment_counter(COUNTER_READS);
    return 0;
}

// ---------------------------------------------------------------------------
// Kprobe: vfs_write — Track file write operations
// ---------------------------------------------------------------------------
SEC("kprobe/vfs_write")
int kprobe_vfs_write(struct pt_regs *ctx) {
    increment_counter(COUNTER_WRITES);
    return 0;
}

// ---------------------------------------------------------------------------
// Kprobe: do_mmap — Track memory mapping
// ---------------------------------------------------------------------------
SEC("kprobe/do_mmap")
int kprobe_do_mmap(struct pt_regs *ctx) {
    increment_counter(COUNTER_MMAP);

    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 pid = pid_tgid >> 32;
    __u64 ts = bpf_ktime_get_ns();

    struct memory_event *event = bpf_ringbuf_reserve(&events, sizeof(*event), 0);
    if (event) {
        event->timestamp_ns = ts;
        event->pid = pid;
        event->address = PT_REGS_PARM1(ctx);
        event->size = PT_REGS_PARM2(ctx);
        event->flags = (__u32)PT_REGS_PARM4(ctx);
        bpf_ringbuf_submit(event, 0);
    }

    return 0;
}

// ---------------------------------------------------------------------------
// Perf Event: CPU cycles — Hardware performance counter
// ---------------------------------------------------------------------------
SEC("perf_event")
int perf_cpu_cycles(struct bpf_perf_event_data *ctx) {
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 cpu = bpf_get_smp_processor_id();

    // Sample CPU cycle count
    __u64 sample_period = ctx->sample_period;

    // Record in LRU map
    __u64 key = ((__u64)cpu << 32) | (pid_tgid & 0xFFFFFFFF);
    bpf_map_update_elem(&recent_events, &key, &sample_period, BPF_ANY);

    return 0;
}

// ---------------------------------------------------------------------------
// Uprobe: Ollama inference tracking
// Attach to Ollama binary to measure inference latency
// ---------------------------------------------------------------------------
SEC("uprobe//usr/local/bin/ollama:main.generateTokens")
int uprobe_ollama_generate(struct pt_regs *ctx) {
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 pid = pid_tgid >> 32;
    __u64 ts = bpf_ktime_get_ns();

    bpf_map_update_elem(&pid_start_times, &pid, &ts, BPF_ANY);
    increment_counter(COUNTER_INFERENCES);

    return 0;
}

SEC("uretprobe//usr/local/bin/ollama:main.generateTokens")
int uretprobe_ollama_generate(struct pt_regs *ctx) {
    __u64 pid_tgid = bpf_get_current_pid_tgid();
    __u32 pid = pid_tgid >> 32;
    __u64 ts = bpf_ktime_get_ns();

    __u64 *start_ts = bpf_map_lookup_elem(&pid_start_times, &pid);
    if (!start_ts) {
        return 0;
    }

    __u64 duration_ns = ts - *start_ts;

    struct inference_event *event = bpf_ringbuf_reserve(&events, sizeof(*event), 0);
    if (event) {
        event->timestamp_ns = ts;
        event->latency_ns = duration_ns;
        event->pid = pid;
        event->tokens_generated = PT_REGS_RC(ctx);
        event->model_id = 0;
        bpf_ringbuf_submit(event, 0);
    }

    bpf_map_delete_elem(&pid_start_times, &pid);
    record_latency(duration_ns);

    return 0;
}

// ---------------------------------------------------------------------------
// XDP: Network packet processing benchmark
// Measures packet processing latency at the network driver level
// ---------------------------------------------------------------------------
SEC("xdp")
int xdp_bench(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;

    // Validate packet bounds
    if (data + 14 > data_end) {
        return XDP_PASS;
    }

    // Count packets
    __u32 key = COUNTER_INTERRUPTS;
    __u64 *val = bpf_map_lookup_elem(&cpu_counters, &key);
    if (val) {
        __sync_fetch_and_add(val, 1);
    }

    // Pass packet to network stack
    return XDP_PASS;
}

// ---------------------------------------------------------------------------
// TC (Traffic Control): Egress packet benchmark
// ---------------------------------------------------------------------------
SEC("tc")
int tc_bench_egress(struct __sk_buff *skb) {
    __u32 key = COUNTER_WRITES;
    __u64 *val = bpf_map_lookup_elem(&cpu_counters, &key);
    if (val) {
        __sync_fetch_and_add(val, 1);
    }
    return TC_ACT_OK;
}

// ---------------------------------------------------------------------------
// LSM (Linux Security Module): Security hook benchmark
// ---------------------------------------------------------------------------
SEC("lsm/file_open")
int lsm_file_open(struct file *file) {
    increment_counter(COUNTER_READS);
    return 0;
}

// ---------------------------------------------------------------------------
// Scheduler: Context switch tracking
// ---------------------------------------------------------------------------
SEC("tracepoint/sched/sched_switch")
int trace_sched_switch(struct trace_event_raw_sched_switch *ctx) {
    increment_counter(COUNTER_CONTEXT_SW);
    return 0;
}

// ---------------------------------------------------------------------------
// Benchmark: Spin loop in eBPF (measures BPF instruction throughput)
// ---------------------------------------------------------------------------
SEC("xdp/spin")
int xdp_spin_bench(struct xdp_md *ctx) {
    __u64 acc = 0;
    __u32 i;

    // 1000 iterations of arithmetic (BPF verifier limits loops)
    #pragma unroll
    for (i = 0; i < 1000; i++) {
        acc = acc * 6364136223846793005ULL + 1442695040888963407ULL;
        acc ^= acc >> 33;
    }

    // Store result to prevent optimization
    __u32 key = 0;
    bpf_map_update_elem(&recent_events, &key, &acc, BPF_ANY);

    return XDP_PASS;
}
