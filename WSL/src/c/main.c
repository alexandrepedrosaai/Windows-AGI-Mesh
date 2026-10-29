/*
 * =============================================================================
 * Windows AGI Benchmark Lab — C Cross-Architecture Benchmark
 * Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
 * =============================================================================
 * Portable C benchmark that compiles for:
 *   - x86_64 (native)
 *   - ARM64 / AArch64 (cross-compiled)
 *   - RISC-V 64-bit (cross-compiled)
 *   - MIPS64 (cross-compiled)
 *   - WebAssembly (emscripten)
 *
 * Build:
 *   Native:   gcc main.c -O2 -o bench_native -lm
 *   ARM64:    aarch64-linux-gnu-gcc main.c -O2 -o bench_arm64 -lm
 *   RISC-V:   riscv64-linux-gnu-gcc main.c -O2 -o bench_riscv64 -lm
 *   MIPS64:   mips64-linux-gnuabi64-gcc main.c -O2 -o bench_mips64 -lm
 *   WASM:     emcc main.c -O2 -o bench.js -lm
 * =============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <inttypes.h>

#ifdef __linux__
#include <unistd.h>
#include <sys/time.h>
#include <sys/resource.h>
#endif

/* ============================================================================
 * Platform Detection
 * ============================================================================ */

#if defined(__x86_64__) || defined(_M_X64)
    #define ARCH_NAME "x86_64"
    #define ARCH_X86_64 1
#elif defined(__aarch64__) || defined(_M_ARM64)
    #define ARCH_NAME "ARM64/AArch64"
    #define ARCH_ARM64 1
#elif defined(__riscv) && (__riscv_xlen == 64)
    #define ARCH_NAME "RISC-V 64-bit"
    #define ARCH_RISCV64 1
#elif defined(__mips64)
    #define ARCH_NAME "MIPS64"
    #define ARCH_MIPS64 1
#elif defined(__powerpc64__)
    #define ARCH_NAME "PowerPC64"
    #define ARCH_PPC64 1
#elif defined(__wasm__)
    #define ARCH_NAME "WebAssembly"
    #define ARCH_WASM 1
#else
    #define ARCH_NAME "Unknown"
#endif

/* ============================================================================
 * Timing
 * ============================================================================ */

typedef struct {
    double elapsed_sec;
    uint64_t iterations;
    double metric;
    const char *unit;
} BenchResult;

static double get_time_sec(void) {
#ifdef __linux__
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1e-9;
#else
    return (double)clock() / CLOCKS_PER_SEC;
#endif
}

/* ============================================================================
 * Benchmark: Integer Arithmetic
 * ============================================================================ */

BenchResult bench_integer_arithmetic(void) {
    const uint64_t ITERS = 10000000ULL;
    volatile uint64_t acc = 0x123456789ABCDEF0ULL;
    volatile uint64_t mul = 0xDEADBEEFCAFEBABEULL;
    volatile uint64_t add = 0x0123456789ABCDEFULL;

    double t0 = get_time_sec();

    for (uint64_t i = 0; i < ITERS; i++) {
        acc = acc * mul + add;
        acc ^= (acc >> 17);
        acc ^= (acc << 31);
        acc ^= (acc >> 43);
        mul = mul * acc + add;
        add = add ^ mul;
    }

    double elapsed = get_time_sec() - t0;
    double mops = (double)(ITERS * 7) / elapsed / 1e6;

    /* Prevent optimization */
    if (acc == 0) printf("(never)\n");

    BenchResult r = {elapsed, ITERS, mops, "MOPS"};
    return r;
}

/* ============================================================================
 * Benchmark: Floating Point (FP64)
 * ============================================================================ */

BenchResult bench_float64(void) {
    const uint64_t ITERS = 5000000ULL;
    const int N = 1024;
    double *a = (double *)malloc(N * sizeof(double));
    double *b = (double *)malloc(N * sizeof(double));
    double *c = (double *)malloc(N * sizeof(double));

    if (!a || !b || !c) {
        free(a); free(b); free(c);
        BenchResult r = {0, 0, 0, "GFLOPS"};
        return r;
    }

    for (int i = 0; i < N; i++) {
        a[i] = (double)i * 0.001 + 1.0;
        b[i] = (double)i * 0.002 + 2.0;
        c[i] = 0.0;
    }

    double t0 = get_time_sec();

    for (uint64_t iter = 0; iter < ITERS / N; iter++) {
        for (int i = 0; i < N; i++) {
            /* FMA: c[i] = a[i] * b[i] + c[i] */
            c[i] = a[i] * b[i] + c[i];
            a[i] = c[i] * 0.5 + b[i];
            b[i] = a[i] + c[i] * 0.25;
        }
    }

    double elapsed = get_time_sec() - t0;
    uint64_t total_flops = (ITERS / N) * N * 5ULL; /* 5 FLOPs per inner iteration */
    double gflops = (double)total_flops / elapsed / 1e9;

    /* Prevent optimization */
    if (c[0] == 0.0 && c[1] == 0.0) printf("(never)\n");

    free(a); free(b); free(c);

    BenchResult r = {elapsed, ITERS, gflops, "GFLOPS"};
    return r;
}

/* ============================================================================
 * Benchmark: Matrix Multiplication (NxN)
 * ============================================================================ */

BenchResult bench_matmul(int N) {
    float *A = (float *)malloc(N * N * sizeof(float));
    float *B = (float *)malloc(N * N * sizeof(float));
    float *C = (float *)malloc(N * N * sizeof(float));

    if (!A || !B || !C) {
        free(A); free(B); free(C);
        BenchResult r = {0, 0, 0, "GFLOPS"};
        return r;
    }

    /* Initialize matrices */
    for (int i = 0; i < N * N; i++) {
        A[i] = (float)(i % 100) * 0.01f + 0.1f;
        B[i] = (float)(i % 100) * 0.02f + 0.2f;
        C[i] = 0.0f;
    }

    double t0 = get_time_sec();

    /* Naive matrix multiplication (compiler may auto-vectorize) */
    for (int i = 0; i < N; i++) {
        for (int k = 0; k < N; k++) {
            float a_ik = A[i * N + k];
            for (int j = 0; j < N; j++) {
                C[i * N + j] += a_ik * B[k * N + j];
            }
        }
    }

    double elapsed = get_time_sec() - t0;
    double flops = 2.0 * (double)N * (double)N * (double)N;
    double gflops = flops / elapsed / 1e9;

    /* Prevent optimization */
    if (C[0] == 0.0f && C[1] == 0.0f) printf("(never)\n");

    free(A); free(B); free(C);

    BenchResult r = {elapsed, (uint64_t)(N * N), gflops, "GFLOPS"};
    return r;
}

/* ============================================================================
 * Benchmark: Memory Bandwidth
 * ============================================================================ */

BenchResult bench_memory_bandwidth(size_t size_mb) {
    size_t n = (size_mb * 1024 * 1024) / sizeof(double);
    double *src = (double *)malloc(n * sizeof(double));
    double *dst = (double *)malloc(n * sizeof(double));

    if (!src || !dst) {
        free(src); free(dst);
        BenchResult r = {0, 0, 0, "GB/s"};
        return r;
    }

    /* Initialize */
    for (size_t i = 0; i < n; i++) {
        src[i] = (double)i * 0.001;
    }

    /* Warmup */
    memcpy(dst, src, n * sizeof(double));

    double t0 = get_time_sec();

    /* Benchmark: copy */
    const int REPS = 5;
    for (int r = 0; r < REPS; r++) {
        memcpy(dst, src, n * sizeof(double));
    }

    double elapsed = get_time_sec() - t0;
    double bytes = (double)REPS * n * sizeof(double) * 2.0; /* read + write */
    double gbs = bytes / elapsed / 1e9;

    /* Prevent optimization */
    if (dst[0] == 0.0 && dst[1] == 0.0) printf("(never)\n");

    free(src); free(dst);

    BenchResult r = {elapsed, (uint64_t)n, gbs, "GB/s"};
    return r;
}

/* ============================================================================
 * Benchmark: Memory Latency (pointer chasing)
 * ============================================================================ */

BenchResult bench_memory_latency(size_t size_bytes) {
    size_t n = size_bytes / sizeof(size_t);
    if (n < 64) n = 64;

    size_t *arr = (size_t *)malloc(n * sizeof(size_t));
    if (!arr) {
        BenchResult r = {0, 0, 0, "ns"};
        return r;
    }

    /* Create random pointer chain */
    for (size_t i = 0; i < n; i++) {
        arr[i] = i;
    }

    /* Fisher-Yates shuffle */
    srand(42);
    for (size_t i = n - 1; i > 0; i--) {
        size_t j = (size_t)rand() % (i + 1);
        size_t tmp = arr[i];
        arr[i] = arr[j];
        arr[j] = tmp;
    }

    /* Build pointer chain */
    size_t *chain = (size_t *)malloc(n * sizeof(size_t));
    if (!chain) {
        free(arr);
        BenchResult r = {0, 0, 0, "ns"};
        return r;
    }

    for (size_t i = 0; i < n; i++) {
        chain[arr[i]] = arr[(i + 1) % n];
    }

    /* Benchmark: pointer chasing */
    const uint64_t ACCESSES = 1000000ULL;
    size_t idx = 0;

    double t0 = get_time_sec();

    for (uint64_t i = 0; i < ACCESSES; i++) {
        idx = chain[idx];
    }

    double elapsed = get_time_sec() - t0;
    double latency_ns = elapsed / (double)ACCESSES * 1e9;

    /* Prevent optimization */
    if (idx == SIZE_MAX) printf("(never)\n");

    free(arr);
    free(chain);

    BenchResult r = {elapsed, ACCESSES, latency_ns, "ns"};
    return r;
}

/* ============================================================================
 * Benchmark: String Operations
 * ============================================================================ */

BenchResult bench_string_ops(void) {
    const size_t STR_LEN = 1024 * 1024; /* 1 MB */
    const int REPS = 100;

    char *src = (char *)malloc(STR_LEN + 1);
    char *dst = (char *)malloc(STR_LEN + 1);

    if (!src || !dst) {
        free(src); free(dst);
        BenchResult r = {0, 0, 0, "GB/s"};
        return r;
    }

    memset(src, 'A', STR_LEN);
    src[STR_LEN] = '\0';

    double t0 = get_time_sec();

    for (int r = 0; r < REPS; r++) {
        memcpy(dst, src, STR_LEN);
        memset(dst, 'B', STR_LEN / 2);
        (void)strlen(src);
        (void)memcmp(src, dst, STR_LEN / 4);
    }

    double elapsed = get_time_sec() - t0;
    double bytes = (double)REPS * STR_LEN * 4.0;
    double gbs = bytes / elapsed / 1e9;

    free(src); free(dst);

    BenchResult r = {elapsed, (uint64_t)REPS, gbs, "GB/s"};
    return r;
}

/* ============================================================================
 * Benchmark: Sorting
 * ============================================================================ */

static int compare_int64(const void *a, const void *b) {
    int64_t ia = *(const int64_t *)a;
    int64_t ib = *(const int64_t *)b;
    return (ia > ib) - (ia < ib);
}

BenchResult bench_sort(void) {
    const int N = 1000000;
    int64_t *arr = (int64_t *)malloc(N * sizeof(int64_t));
    int64_t *tmp = (int64_t *)malloc(N * sizeof(int64_t));

    if (!arr || !tmp) {
        free(arr); free(tmp);
        BenchResult r = {0, 0, 0, "Melements/s"};
        return r;
    }

    /* Generate random data */
    srand(42);
    for (int i = 0; i < N; i++) {
        arr[i] = ((int64_t)rand() << 32) | rand();
        tmp[i] = arr[i];
    }

    double t0 = get_time_sec();

    qsort(arr, N, sizeof(int64_t), compare_int64);

    double elapsed = get_time_sec() - t0;
    double melems_per_sec = (double)N / elapsed / 1e6;

    free(arr); free(tmp);

    BenchResult r = {elapsed, (uint64_t)N, melems_per_sec, "Melements/s"};
    return r;
}

/* ============================================================================
 * Benchmark: Transcendental Functions
 * ============================================================================ */

BenchResult bench_transcendental(void) {
    const uint64_t ITERS = 1000000ULL;
    volatile double acc = 1.0;

    double t0 = get_time_sec();

    for (uint64_t i = 1; i <= ITERS; i++) {
        double x = (double)i * 0.000001;
        acc += sin(x) + cos(x) + sqrt(x) + log(x + 1.0) + exp(-x);
    }

    double elapsed = get_time_sec() - t0;
    double mops = (double)(ITERS * 5) / elapsed / 1e6;

    if (acc == 0.0) printf("(never)\n");

    BenchResult r = {elapsed, ITERS, mops, "MOPS"};
    return r;
}

/* ============================================================================
 * Benchmark: Compression (simple RLE)
 * ============================================================================ */

static size_t rle_compress(const uint8_t *src, size_t src_len, uint8_t *dst) {
    size_t dst_pos = 0;
    size_t i = 0;

    while (i < src_len) {
        uint8_t val = src[i];
        size_t run = 1;

        while (i + run < src_len && src[i + run] == val && run < 255) {
            run++;
        }

        dst[dst_pos++] = (uint8_t)run;
        dst[dst_pos++] = val;
        i += run;
    }

    return dst_pos;
}

BenchResult bench_compression(void) {
    const size_t DATA_SIZE = 1024 * 1024; /* 1 MB */
    const int REPS = 50;

    uint8_t *src = (uint8_t *)malloc(DATA_SIZE);
    uint8_t *dst = (uint8_t *)malloc(DATA_SIZE * 2);

    if (!src || !dst) {
        free(src); free(dst);
        BenchResult r = {0, 0, 0, "MB/s"};
        return r;
    }

    /* Generate compressible data */
    for (size_t i = 0; i < DATA_SIZE; i++) {
        src[i] = (uint8_t)(i % 16); /* repeating pattern */
    }

    double t0 = get_time_sec();

    size_t compressed_size = 0;
    for (int r = 0; r < REPS; r++) {
        compressed_size = rle_compress(src, DATA_SIZE, dst);
    }

    double elapsed = get_time_sec() - t0;
    double mb_per_sec = (double)REPS * DATA_SIZE / elapsed / (1024 * 1024);

    printf("  Compression ratio: %.2fx (%zu -> %zu bytes)\n",
           (double)DATA_SIZE / (double)compressed_size,
           DATA_SIZE, compressed_size);

    free(src); free(dst);

    BenchResult r = {elapsed, (uint64_t)REPS, mb_per_sec, "MB/s"};
    return r;
}

/* ============================================================================
 * Benchmark: Hash (FNV-1a 64-bit)
 * ============================================================================ */

static uint64_t fnv1a_64(const uint8_t *data, size_t len) {
    uint64_t hash = 14695981039346656037ULL;
    for (size_t i = 0; i < len; i++) {
        hash ^= (uint64_t)data[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

BenchResult bench_hash(void) {
    const size_t DATA_SIZE = 1024 * 1024;
    const int REPS = 100;

    uint8_t *data = (uint8_t *)malloc(DATA_SIZE);
    if (!data) {
        BenchResult r = {0, 0, 0, "GB/s"};
        return r;
    }

    for (size_t i = 0; i < DATA_SIZE; i++) {
        data[i] = (uint8_t)(i * 7 + 13);
    }

    double t0 = get_time_sec();

    volatile uint64_t hash = 0;
    for (int r = 0; r < REPS; r++) {
        hash ^= fnv1a_64(data, DATA_SIZE);
    }

    double elapsed = get_time_sec() - t0;
    double gbs = (double)REPS * DATA_SIZE / elapsed / 1e9;

    if (hash == 0) printf("(never)\n");

    free(data);

    BenchResult r = {elapsed, (uint64_t)REPS, gbs, "GB/s"};
    return r;
}

/* ============================================================================
 * System Information
 * ============================================================================ */

static void print_system_info(void) {
    printf("=================================================================\n");
    printf("  Windows AGI Benchmark Lab — C Cross-Architecture Benchmark\n");
    printf("  Microsoft Corporation — Exclusive License\n");
    printf("=================================================================\n");
    printf("  Architecture:  %s\n", ARCH_NAME);
    printf("  Compiler:      %s\n",
#if defined(__clang__)
        "Clang " __clang_version__
#elif defined(__GNUC__)
        "GCC " __VERSION__
#elif defined(_MSC_VER)
        "MSVC"
#else
        "Unknown"
#endif
    );
    printf("  C Standard:    C%d\n", __STDC_VERSION__ / 100 % 100);
    printf("  Pointer size:  %zu bytes\n", sizeof(void *));
    printf("  int size:      %zu bytes\n", sizeof(int));
    printf("  long size:     %zu bytes\n", sizeof(long));
    printf("  double size:   %zu bytes\n", sizeof(double));

#ifdef __linux__
    /* Read /proc/cpuinfo for CPU model */
    FILE *f = fopen("/proc/cpuinfo", "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            if (strncmp(line, "model name", 10) == 0) {
                char *colon = strchr(line, ':');
                if (colon) {
                    printf("  CPU:           %s", colon + 2);
                    break;
                }
            }
        }
        fclose(f);
    }
#endif

    printf("=================================================================\n\n");
}

/* ============================================================================
 * Print Result
 * ============================================================================ */

static void print_result(const char *name, BenchResult r) {
    printf("  %-35s %10.3f %-12s  (%.3fs, %"PRIu64" iters)\n",
           name, r.metric, r.unit, r.elapsed_sec, r.iterations);
}

/* ============================================================================
 * Main
 * ============================================================================ */

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    print_system_info();

    printf("Running benchmarks...\n\n");

    BenchResult r;

    /* Integer arithmetic */
    printf("[ Integer Arithmetic ]\n");
    r = bench_integer_arithmetic();
    print_result("Integer multiply-add-xor", r);

    /* Floating point */
    printf("\n[ Floating Point ]\n");
    r = bench_float64();
    print_result("FP64 FMA array", r);

    /* Matrix multiplication */
    printf("\n[ Matrix Multiplication ]\n");
    int sizes[] = {128, 256, 512, 1024};
    for (int i = 0; i < 4; i++) {
        char name[64];
        snprintf(name, sizeof(name), "MatMul %dx%d (FP32)", sizes[i], sizes[i]);
        r = bench_matmul(sizes[i]);
        print_result(name, r);
    }

    /* Memory bandwidth */
    printf("\n[ Memory Bandwidth ]\n");
    size_t mem_sizes[] = {1, 4, 16, 64, 256};
    for (int i = 0; i < 5; i++) {
        char name[64];
        snprintf(name, sizeof(name), "Memory copy %zuMB", mem_sizes[i]);
        r = bench_memory_bandwidth(mem_sizes[i]);
        print_result(name, r);
    }

    /* Memory latency */
    printf("\n[ Memory Latency ]\n");
    size_t lat_sizes[] = {
        32 * 1024,          /* 32 KB  — L1 cache */
        256 * 1024,         /* 256 KB — L2 cache */
        8 * 1024 * 1024,    /* 8 MB   — L3 cache */
        256 * 1024 * 1024,  /* 256 MB — Main RAM */
    };
    const char *lat_names[] = {"L1 cache (32KB)", "L2 cache (256KB)", "L3 cache (8MB)", "Main RAM (256MB)"};
    for (int i = 0; i < 4; i++) {
        r = bench_memory_latency(lat_sizes[i]);
        print_result(lat_names[i], r);
    }

    /* String operations */
    printf("\n[ String Operations ]\n");
    r = bench_string_ops();
    print_result("memcpy/memset/strlen/memcmp", r);

    /* Sorting */
    printf("\n[ Sorting ]\n");
    r = bench_sort();
    print_result("qsort 1M int64", r);

    /* Transcendental functions */
    printf("\n[ Transcendental Functions ]\n");
    r = bench_transcendental();
    print_result("sin+cos+sqrt+log+exp", r);

    /* Compression */
    printf("\n[ Compression ]\n");
    r = bench_compression();
    print_result("RLE compress 1MB", r);

    /* Hash */
    printf("\n[ Hash ]\n");
    r = bench_hash();
    print_result("FNV-1a 64-bit 1MB", r);

    printf("\n=================================================================\n");
    printf("  Benchmark complete — Architecture: %s\n", ARCH_NAME);
    printf("  Microsoft Corporation — Windows AGI Benchmark Lab\n");
    printf("=================================================================\n");

    return 0;
}
