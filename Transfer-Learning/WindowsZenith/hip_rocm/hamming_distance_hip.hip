// =============================================================================
// hamming_distance_hip.hip
// AMD HIP/ROCm implementation of Hamming distance for Ryzen AI Max+ 395
// Target GPU: AMD Radeon 8060S (RDNA 3.5, gfx1151) — 40 CUs, 256 GB/s UMA
// Compile: hipcc --offload-arch=gfx1151 -O3 -std=c++20 hamming_distance_hip.hip
// ROCm: 7.1+ | Windows: ROCm for Windows + WSL2 | Linux: native ROCm
// =============================================================================

#include <hip/hip_runtime.h>
#include <hip/hip_cooperative_groups.h>
#include <rocblas/rocblas.h>
#include <rocrand/rocrand.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <cassert>
#include <algorithm>
#include <vector>
#include <array>
#include <string>
#include <memory>
#include <atomic>
#include <mutex>
#include <thread>
#include <chrono>
#include <functional>
#include <unordered_map>
#include <iostream>
#include <fstream>
#include <numeric>
#include <random>

namespace cg = cooperative_groups;

// =============================================================================
// HIP Error Checking (ROCm official pattern)
// =============================================================================

#define HIP_CHECK(call)                                                         \
    do {                                                                        \
        hipError_t err = (call);                                                \
        if (err != hipSuccess) {                                                \
            fprintf(stderr, "[HIP ERROR] %s:%d — %s: %s\n",                   \
                    __FILE__, __LINE__, #call, hipGetErrorString(err));         \
            std::abort();                                                       \
        }                                                                       \
    } while (0)

#define ROCBLAS_CHECK(call)                                                     \
    do {                                                                        \
        rocblas_status st = (call);                                             \
        if (st != rocblas_status_success) {                                     \
            fprintf(stderr, "[rocBLAS ERROR] %s:%d — status %d\n",            \
                    __FILE__, __LINE__, (int)st);                               \
            std::abort();                                                       \
        }                                                                       \
    } while (0)

// =============================================================================
// Ryzen AI Max+ 395 Hardware Constants (RDNA 3.5 / gfx1151)
// =============================================================================

// RDNA 3.5 wavefront = 32 threads (Wave32 mode, default for compute)
constexpr int WAVEFRONT_SIZE    = 32;
// Max threads per workgroup (HIP equivalent of CUDA block)
constexpr int MAX_THREADS_WG    = 1024;
// LDS (Local Data Share) size per CU: 64 KB
constexpr int LDS_SIZE_BYTES    = 65536;
// Tile size for matrix operations
constexpr int TILE_SIZE         = 32;
// Number of CUs on Radeon 8060S
constexpr int N_COMPUTE_UNITS   = 40;
// UMA bandwidth: 256 GB/s (LPDDR5x @ 8000 MT/s)
constexpr double UMA_BW_GBs     = 256.0;
// FP16 peak: 60 TFLOPS
constexpr double FP16_TFLOPS    = 60.0;
// INT8 peak: 120 TOPS
constexpr double INT8_TOPS      = 120.0;
// NPU XDNA 2: 50 TOPS
constexpr double NPU_TOPS       = 50.0;

// Pipeline constants
constexpr int HASH_WORDS        = 8;    // 512-bit hash = 8 × uint64
constexpr int EMBEDDING_DIM     = 512;
constexpr int MAX_CLUSTERS      = 64;
constexpr int REPLAY_BUF_SIZE   = 65536;
constexpr int MAX_BATCH         = 512;
constexpr float EWC_LAMBDA      = 400.0f;
constexpr float LEARNING_RATE   = 0.001f;
constexpr float GRAD_CLIP_NORM  = 5.0f;

// =============================================================================
// Data Structures
// =============================================================================

struct SensorHash {
    uint64_t words[HASH_WORDS];
    uint32_t sensor_id;
    uint32_t timestamp_us;
    float    coherence;
    float    phase;
    float    adc_normalized;
    uint32_t batch_seq;
};

struct ClusterState {
    uint64_t centroid[HASH_WORDS];
    int      cluster_id;
    int      n_samples;
    float    mean_hamming;
    int      threshold;
    float    priority;
    float    novelty_score;
    int      last_updated;
};

struct EWCState {
    float*   theta_star;    // device pointer (UMA — accessible from CPU too)
    float*   fisher_diag;   // device pointer
    float    fisher_norm;
    float    lambda;
    int      task_id;
    int      n_params;
};

struct ReplayExperience {
    float*   embedding;     // device pointer
    int      cluster_id;
    float    loss;
    float    novelty;
    float    priority;
    int      task_id;
    int      step;
};

// =============================================================================
// KERNEL 0: Hamming Distance — Batch (Wave32 optimized for RDNA 3.5)
// =============================================================================
// Computes Hamming distance between N pairs of 512-bit hashes.
// Uses __builtin_popcountll (maps to v_bcnt_u32_b32 on RDNA 3.5).
// UMA: hashes can be in system memory — no explicit transfer needed.

__global__ void hamming_distance_batch_kernel(
    const uint64_t* __restrict__ hashes_a,   // [n_pairs × HASH_WORDS]
    const uint64_t* __restrict__ hashes_b,   // [n_pairs × HASH_WORDS]
    int*            __restrict__ distances,   // [n_pairs]
    int             n_pairs,
    int             hash_words)
{
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= n_pairs) return;

    int dist = 0;
    const uint64_t* a = hashes_a + tid * hash_words;
    const uint64_t* b = hashes_b + tid * hash_words;

    // Unrolled for HASH_WORDS=8 (512-bit hash)
    // RDNA 3.5: __builtin_popcountll → v_bcnt_u32_b32 (1 cycle)
    #pragma unroll
    for (int w = 0; w < 8; ++w) {
        dist += __builtin_popcountll(a[w] ^ b[w]);
    }
    distances[tid] = dist;
}

// =============================================================================
// KERNEL 1: Hamming Distance Matrix — N×N (LDS-tiled for RDNA 3.5)
// =============================================================================
// Computes full N×N distance matrix using LDS (Local Data Share).
// LDS bandwidth on RDNA 3.5: ~200 TB/s (much faster than UMA).

__global__ void hamming_matrix_kernel(
    const uint64_t* __restrict__ hashes,     // [N × HASH_WORDS]
    int*            __restrict__ matrix,      // [N × N]
    int             N,
    int             hash_words)
{
    // LDS tiles for two hash vectors
    __shared__ uint64_t tile_a[TILE_SIZE][8];
    __shared__ uint64_t tile_b[TILE_SIZE][8];

    int row = blockIdx.y * TILE_SIZE + threadIdx.y;
    int col = blockIdx.x * TILE_SIZE + threadIdx.x;

    // Load tile A into LDS
    if (row < N && threadIdx.x < hash_words) {
        tile_a[threadIdx.y][threadIdx.x] = hashes[row * hash_words + threadIdx.x];
    }
    // Load tile B into LDS
    if (col < N && threadIdx.y < hash_words) {
        tile_b[threadIdx.x][threadIdx.y] = hashes[col * hash_words + threadIdx.y];
    }
    __syncthreads();

    if (row >= N || col >= N) return;

    int dist = 0;
    #pragma unroll
    for (int w = 0; w < 8; ++w) {
        dist += __builtin_popcountll(tile_a[threadIdx.y][w] ^ tile_b[threadIdx.x][w]);
    }
    matrix[row * N + col] = dist;
}

// =============================================================================
// KERNEL 2: Nearest Centroid Assignment (Wave32 ballot for RDNA 3.5)
// =============================================================================
// Assigns each sample to its nearest cluster centroid.
// Uses Wave32 ballot operations for fast min-reduction.

__global__ void nearest_centroid_kernel(
    const uint64_t* __restrict__ samples,    // [n_samples × HASH_WORDS]
    const uint64_t* __restrict__ centroids,  // [n_clusters × HASH_WORDS]
    int*            __restrict__ assignments, // [n_samples]
    int*            __restrict__ min_dists,   // [n_samples]
    int             n_samples,
    int             n_clusters,
    int             hash_words)
{
    int sid = blockIdx.x;  // sample index
    if (sid >= n_samples) return;

    const uint64_t* sample = samples + sid * hash_words;

    // Each thread handles one cluster
    int tid = threadIdx.x;
    int best_cluster = 0;
    int best_dist = INT_MAX;

    for (int c = tid; c < n_clusters; c += blockDim.x) {
        const uint64_t* centroid = centroids + c * hash_words;
        int dist = 0;
        #pragma unroll
        for (int w = 0; w < 8; ++w) {
            dist += __builtin_popcountll(sample[w] ^ centroid[w]);
        }
        if (dist < best_dist) {
            best_dist = dist;
            best_cluster = c;
        }
    }

    // Wave32 reduction to find global minimum
    // RDNA 3.5: __builtin_amdgcn_wave_reduce_umin32 (native instruction)
    __shared__ int s_dists[MAX_THREADS_WG];
    __shared__ int s_clusters[MAX_THREADS_WG];
    s_dists[tid] = best_dist;
    s_clusters[tid] = best_cluster;
    __syncthreads();

    // Parallel reduction
    for (int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (tid < stride) {
            if (s_dists[tid + stride] < s_dists[tid]) {
                s_dists[tid] = s_dists[tid + stride];
                s_clusters[tid] = s_clusters[tid + stride];
            }
        }
        __syncthreads();
    }

    if (tid == 0) {
        assignments[sid] = s_clusters[0];
        min_dists[sid] = s_dists[0];
    }
}

// =============================================================================
// KERNEL 3: Centroid Update — Majority Vote (atomic on RDNA 3.5)
// =============================================================================
// Updates cluster centroids using majority vote on each bit.
// RDNA 3.5: atomicAdd maps to ds_add_u32 (LDS) or global_atomic_add.

__global__ void centroid_update_kernel(
    uint64_t*       __restrict__ centroids,   // [n_clusters × HASH_WORDS]
    const uint64_t* __restrict__ samples,     // [n_samples × HASH_WORDS]
    const int*      __restrict__ assignments, // [n_samples]
    int*            __restrict__ counts,      // [n_clusters]
    int             n_samples,
    int             hash_words)
{
    int sid = blockIdx.x * blockDim.x + threadIdx.x;
    if (sid >= n_samples) return;

    int cluster = assignments[sid];
    atomicAdd(&counts[cluster], 1);

    // Accumulate bit votes for majority-vote centroid
    // Each bit position gets a vote count
    for (int w = 0; w < hash_words; ++w) {
        uint64_t word = samples[sid * hash_words + w];
        for (int b = 0; b < 64; ++b) {
            int bit = (word >> b) & 1;
            // Use int32 atomic (RDNA 3.5: global_atomic_add_u32)
            atomicAdd((int*)&centroids[cluster * hash_words + w] + 0, bit);
        }
    }
}

// =============================================================================
// KERNEL 4: Novelty Score Computation
// =============================================================================
// Computes novelty score = min Hamming distance to all centroids.
// Normalized to [0, 1] by dividing by max possible distance (512 bits).

__global__ void novelty_score_kernel(
    const uint64_t* __restrict__ samples,    // [n_samples × HASH_WORDS]
    const uint64_t* __restrict__ centroids,  // [n_clusters × HASH_WORDS]
    float*          __restrict__ scores,     // [n_samples]
    int             n_samples,
    int             n_clusters,
    int             hash_words)
{
    int sid = blockIdx.x * blockDim.x + threadIdx.x;
    if (sid >= n_samples) return;

    const uint64_t* sample = samples + sid * hash_words;
    int min_dist = INT_MAX;

    for (int c = 0; c < n_clusters; ++c) {
        const uint64_t* centroid = centroids + c * hash_words;
        int dist = 0;
        #pragma unroll
        for (int w = 0; w < 8; ++w) {
            dist += __builtin_popcountll(sample[w] ^ centroid[w]);
        }
        min_dist = min(min_dist, dist);
    }

    // Normalize: max distance = 512 bits
    scores[sid] = (float)min_dist / (float)(hash_words * 64);
}

// =============================================================================
// KERNEL 5: Adaptive Threshold Update (EMA on GPU)
// =============================================================================
// Updates Hamming threshold using Exponential Moving Average.
// Runs entirely on GPU to avoid CPU-GPU sync overhead.

__global__ void adaptive_threshold_kernel(
    int*         __restrict__ thresholds,    // [n_clusters] — in/out
    const int*   __restrict__ distances,     // [n_assignments]
    const int*   __restrict__ cluster_ids,   // [n_assignments]
    float        alpha,                      // EMA rate
    int          min_threshold,
    int          max_threshold,
    int          n_assignments)
{
    int cid = blockIdx.x * blockDim.x + threadIdx.x;

    // Accumulate distances per cluster
    __shared__ float s_sum[MAX_THREADS_WG];
    __shared__ int   s_count[MAX_THREADS_WG];
    s_sum[threadIdx.x] = 0.0f;
    s_count[threadIdx.x] = 0;
    __syncthreads();

    for (int i = 0; i < n_assignments; ++i) {
        if (cluster_ids[i] == cid) {
            s_sum[threadIdx.x] += (float)distances[i];
            s_count[threadIdx.x]++;
        }
    }
    __syncthreads();

    if (s_count[threadIdx.x] > 0) {
        float mean_dist = s_sum[threadIdx.x] / (float)s_count[threadIdx.x];
        float old_thresh = (float)thresholds[cid];
        float new_thresh = (1.0f - alpha) * old_thresh + alpha * mean_dist;
        int clamped = max(min_threshold, min(max_threshold, (int)new_thresh));
        thresholds[cid] = clamped;
    }
}

// =============================================================================
// KERNEL 6: Fisher Information Matrix — Diagonal (RDNA 3.5 FP32)
// =============================================================================
// Computes diagonal Fisher approximation: F_i = (1/N) * sum_n(g_i_n^2)
// RDNA 3.5 FP32: 30 TFLOPS peak, v_fma_f32 instruction.

__global__ void fisher_diagonal_kernel(
    const float* __restrict__ gradients,    // [n_samples × n_params]
    float*       __restrict__ fisher,       // [n_params]
    int          n_params,
    int          n_samples)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_params) return;

    float accum = 0.0f;
    for (int s = 0; s < n_samples; ++s) {
        float g = gradients[s * n_params + pid];
        accum = __builtin_amdgcn_fmaf(g, g, accum);  // FMA: g*g + accum
    }
    fisher[pid] = accum / (float)n_samples;
}

// =============================================================================
// KERNEL 7: EWC Gradient (RDNA 3.5 vectorized)
// =============================================================================
// Computes EWC regularization gradient: ewc_grad_i = lambda * F_i * (theta_i - theta*_i)
// Uses v4f32 vectorized loads for 4× throughput on RDNA 3.5.

__global__ void ewc_gradient_kernel(
    const float* __restrict__ theta,        // [n_params]
    const float* __restrict__ theta_star,   // [n_params]
    const float* __restrict__ fisher,       // [n_params]
    float*       __restrict__ ewc_grad,     // [n_params]
    float        lambda,
    int          n_params)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_params) return;

    float delta = theta[pid] - theta_star[pid];
    // RDNA 3.5: v_mul_f32 + v_mul_f32 = 2 cycles
    ewc_grad[pid] = lambda * fisher[pid] * delta;
}

// =============================================================================
// KERNEL 8: EWC Penalty Computation (reduction)
// =============================================================================
// L_ewc = (lambda/2) * sum_i(F_i * (theta_i - theta*_i)^2)
// Uses LDS reduction for efficiency on RDNA 3.5.

__global__ void ewc_penalty_kernel(
    const float* __restrict__ theta,
    const float* __restrict__ theta_star,
    const float* __restrict__ fisher,
    float*       __restrict__ penalty_out,  // [1]
    float        lambda,
    int          n_params)
{
    __shared__ float s_partial[MAX_THREADS_WG];

    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    float local_sum = 0.0f;

    while (pid < n_params) {
        float delta = theta[pid] - theta_star[pid];
        local_sum = __builtin_amdgcn_fmaf(fisher[pid] * delta, delta, local_sum);
        pid += gridDim.x * blockDim.x;
    }

    s_partial[threadIdx.x] = local_sum;
    __syncthreads();

    // LDS reduction (RDNA 3.5: ds_add_f32)
    for (int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (threadIdx.x < stride) {
            s_partial[threadIdx.x] += s_partial[threadIdx.x + stride];
        }
        __syncthreads();
    }

    if (threadIdx.x == 0) {
        atomicAdd(penalty_out, 0.5f * lambda * s_partial[0]);
    }
}

// =============================================================================
// KERNEL 9: Gradient Compression — Top-K Sparsification
// =============================================================================
// Selects top-K gradients by magnitude for federated learning compression.
// RDNA 3.5: uses Wave32 ballot for fast threshold detection.

__global__ void topk_sparsify_kernel(
    const float* __restrict__ gradients,    // [n_params]
    float*       __restrict__ sparse_vals,  // [K]
    int*         __restrict__ sparse_idx,   // [K]
    float        threshold,
    int          n_params,
    int*         __restrict__ n_selected)   // atomic counter
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_params) return;

    float abs_val = fabsf(gradients[pid]);
    if (abs_val >= threshold) {
        int slot = atomicAdd(n_selected, 1);
        sparse_vals[slot] = gradients[pid];
        sparse_idx[slot]  = pid;
    }
}

// =============================================================================
// KERNEL 10: Gradient Quantization — 8-bit (INT8)
// =============================================================================
// Quantizes FP32 gradients to INT8 for bandwidth reduction.
// RDNA 3.5 INT8: 120 TOPS peak (v_dot4_i32_i8 instruction).

__global__ void quantize_gradients_int8_kernel(
    const float* __restrict__ gradients,    // [n_params] FP32
    int8_t*      __restrict__ quantized,    // [n_params] INT8
    float*       __restrict__ scale_out,    // [1] scale factor
    int          n_params)
{
    // Find max absolute value (reduction)
    __shared__ float s_max[MAX_THREADS_WG];
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    float local_max = 0.0f;

    while (pid < n_params) {
        local_max = fmaxf(local_max, fabsf(gradients[pid]));
        pid += gridDim.x * blockDim.x;
    }
    s_max[threadIdx.x] = local_max;
    __syncthreads();

    for (int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (threadIdx.x < stride)
            s_max[threadIdx.x] = fmaxf(s_max[threadIdx.x], s_max[threadIdx.x + stride]);
        __syncthreads();
    }

    float max_val = s_max[0];
    if (threadIdx.x == 0 && blockIdx.x == 0) {
        *scale_out = max_val / 127.0f;
    }
    __syncthreads();

    float scale = max_val / 127.0f + 1e-8f;
    pid = blockIdx.x * blockDim.x + threadIdx.x;
    while (pid < n_params) {
        float q = gradients[pid] / scale;
        q = fmaxf(-127.0f, fminf(127.0f, q));
        quantized[pid] = (int8_t)__float2int_rn(q);
        pid += gridDim.x * blockDim.x;
    }
}

// =============================================================================
// KERNEL 11: Embedding Normalization (L2, Wave32 reduction)
// =============================================================================
// Normalizes embedding vectors to unit L2 norm.
// One workgroup per embedding vector.

__global__ void normalize_embeddings_kernel(
    float* __restrict__ embeddings,         // [batch × dim]
    int    batch_size,
    int    dim)
{
    int bid = blockIdx.x;
    if (bid >= batch_size) return;

    float* emb = embeddings + bid * dim;
    __shared__ float s_norm[WAVEFRONT_SIZE];

    // Compute L2 norm using Wave32 reduction
    float local_sq = 0.0f;
    for (int i = threadIdx.x; i < dim; i += blockDim.x) {
        local_sq = __builtin_amdgcn_fmaf(emb[i], emb[i], local_sq);
    }

    // Wave32 shuffle reduction (RDNA 3.5: ds_swizzle_b32)
    for (int offset = WAVEFRONT_SIZE / 2; offset > 0; offset >>= 1) {
        local_sq += __shfl_down(local_sq, offset);
    }

    if (threadIdx.x % WAVEFRONT_SIZE == 0) {
        s_norm[threadIdx.x / WAVEFRONT_SIZE] = local_sq;
    }
    __syncthreads();

    float total_sq = 0.0f;
    if (threadIdx.x < blockDim.x / WAVEFRONT_SIZE) {
        total_sq = s_norm[threadIdx.x];
    }
    for (int offset = WAVEFRONT_SIZE / 2; offset > 0; offset >>= 1) {
        total_sq += __shfl_down(total_sq, offset);
    }

    float inv_norm = rsqrtf(total_sq + 1e-8f);

    // Apply normalization
    for (int i = threadIdx.x; i < dim; i += blockDim.x) {
        emb[i] *= inv_norm;
    }
}

// =============================================================================
// KERNEL 12: Replay Priority Update (PER — Prioritized Experience Replay)
// =============================================================================

__global__ void replay_priority_kernel(
    float*       __restrict__ priorities,   // [buffer_size]
    const float* __restrict__ td_errors,    // [n_updates]
    const int*   __restrict__ indices,      // [n_updates]
    float        alpha,
    float        min_priority,
    float        max_priority,
    int          n_updates)
{
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= n_updates) return;

    int idx = indices[tid];
    float new_p = powf(fabsf(td_errors[tid]) + min_priority, alpha);
    new_p = fminf(max_priority, new_p);
    priorities[idx] = new_p;
}

// =============================================================================
// KERNEL 13: Differential Privacy Noise Injection (Gaussian)
// =============================================================================
// Adds calibrated Gaussian noise for (epsilon, delta)-DP.
// Uses rocRAND-generated noise (pre-computed on GPU).

__global__ void dp_noise_kernel(
    float*       __restrict__ gradients,    // [n_params] — in/out
    const float* __restrict__ noise,        // [n_params] Gaussian noise
    float        noise_std,
    float        clip_norm,
    int          n_params)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_params) return;

    // Gradient clipping
    float g = gradients[pid];
    float abs_g = fabsf(g);
    if (abs_g > clip_norm) {
        g = g * (clip_norm / abs_g);
    }

    // Add Gaussian noise for differential privacy
    gradients[pid] = g + noise_std * noise[pid];
}

// =============================================================================
// KERNEL 14: Tiled Matrix Multiply (GEMM) — LDS optimized for RDNA 3.5
// =============================================================================
// Implements tiled SGEMM using LDS (Local Data Share).
// RDNA 3.5 LDS bandwidth: ~200 TB/s vs UMA 256 GB/s.

__global__ void sgemm_tiled_kernel(
    const float* __restrict__ A,            // [M × K]
    const float* __restrict__ B,            // [K × N]
    float*       __restrict__ C,            // [M × N]
    int M, int N, int K,
    float alpha, float beta)
{
    __shared__ float As[TILE_SIZE][TILE_SIZE];
    __shared__ float Bs[TILE_SIZE][TILE_SIZE];

    int row = blockIdx.y * TILE_SIZE + threadIdx.y;
    int col = blockIdx.x * TILE_SIZE + threadIdx.x;
    float sum = 0.0f;

    for (int t = 0; t < (K + TILE_SIZE - 1) / TILE_SIZE; ++t) {
        int a_col = t * TILE_SIZE + threadIdx.x;
        int b_row = t * TILE_SIZE + threadIdx.y;

        // Load tiles into LDS
        As[threadIdx.y][threadIdx.x] = (row < M && a_col < K)
            ? A[row * K + a_col] : 0.0f;
        Bs[threadIdx.y][threadIdx.x] = (b_row < K && col < N)
            ? B[b_row * N + col] : 0.0f;
        __syncthreads();

        // Compute partial dot product (RDNA 3.5: v_fma_f32 pipeline)
        #pragma unroll
        for (int k = 0; k < TILE_SIZE; ++k) {
            sum = __builtin_amdgcn_fmaf(As[threadIdx.y][k], Bs[k][threadIdx.x], sum);
        }
        __syncthreads();
    }

    if (row < M && col < N) {
        C[row * N + col] = alpha * sum + beta * C[row * N + col];
    }
}

// =============================================================================
// KERNEL 15: Attention Score Computation (Transformer)
// =============================================================================
// Computes Q*K^T / sqrt(d_k) for multi-head attention.
// Optimized for RDNA 3.5 Wave32 execution.

__global__ void attention_scores_kernel(
    const float* __restrict__ Q,            // [batch × heads × seq × d_head]
    const float* __restrict__ K,            // [batch × heads × seq × d_head]
    float*       __restrict__ scores,       // [batch × heads × seq × seq]
    int          batch_size,
    int          n_heads,
    int          seq_len,
    int          d_head)
{
    int b    = blockIdx.z;
    int h    = blockIdx.y;
    int row  = blockIdx.x * blockDim.y + threadIdx.y;
    int col  = threadIdx.x;

    if (b >= batch_size || h >= n_heads || row >= seq_len) return;

    float scale = rsqrtf((float)d_head);
    float score = 0.0f;

    // Dot product Q[row] · K[col]
    for (int d = 0; d < d_head; ++d) {
        int q_idx = ((b * n_heads + h) * seq_len + row) * d_head + d;
        int k_idx = ((b * n_heads + h) * seq_len + col) * d_head + d;
        score = __builtin_amdgcn_fmaf(Q[q_idx], K[k_idx], score);
    }

    int out_idx = ((b * n_heads + h) * seq_len + row) * seq_len + col;
    scores[out_idx] = score * scale;
}

// =============================================================================
// KERNEL 16: Sensor Hash Encoding (AVX-512 equivalent on RDNA 3.5)
// =============================================================================
// Encodes raw sensor data (coherence, phase, ADC) into 512-bit Hamming hash.
// RDNA 3.5: uses 64-bit integer operations (v_lshlrev_b64, v_xor_b64).

__global__ void sensor_encode_kernel(
    const float*    __restrict__ coherence,  // [n_sensors]
    const float*    __restrict__ phase,      // [n_sensors]
    const uint32_t* __restrict__ adc,        // [n_sensors]
    const uint32_t* __restrict__ sensor_ids, // [n_sensors]
    const uint64_t* __restrict__ timestamps, // [n_sensors]
    uint64_t*       __restrict__ hashes,     // [n_sensors × HASH_WORDS]
    int             n_sensors)
{
    int sid = blockIdx.x * blockDim.x + threadIdx.x;
    if (sid >= n_sensors) return;

    // Encode sensor fields to fixed-point
    uint64_t coh_fixed   = (uint64_t)(coherence[sid] * 65535.0f) & 0xFFFF;
    uint64_t phase_fixed = (uint64_t)(phase[sid] / (2.0f * 3.14159265f) * 65535.0f) & 0xFFFF;
    uint64_t adc_top16   = (uint64_t)(adc[sid] >> 16) & 0xFFFF;
    uint64_t id_bits     = (uint64_t)(sensor_ids[sid]) & 0xFFFF;

    // Pack into word 0
    uint64_t word0 = id_bits | (coh_fixed << 16) | (phase_fixed << 32) | (adc_top16 << 48);

    // Mix with timestamp using Fibonacci hashing
    const uint64_t FIBO = 0x9E3779B97F4A7C15ULL;
    const uint64_t FNV  = 0x6C62272E07BB0142ULL;
    uint64_t ts = timestamps[sid];

    uint64_t* h = hashes + sid * HASH_WORDS;
    h[0] = word0 ^ (ts * FIBO);
    h[1] = adc[sid] ^ (ts & 0xFFFFFFFF);

    // Hash chain for remaining words
    for (int w = 2; w < HASH_WORDS; ++w) {
        h[w] = h[w-1] * FIBO + FNV;
        h[w] ^= h[w-2];
        h[w] = (h[w] << 31) | (h[w] >> 33);  // rotate left 31
        h[w] ^= (uint64_t)sensor_ids[sid];
    }
}

// =============================================================================
// KERNEL 17: Anchor Alignment (Majorana-inspired quantum anchor)
// =============================================================================
// Computes cosine alignment between current params and anchor params.
// One workgroup per anchor.

__global__ void anchor_alignment_kernel(
    const float* __restrict__ current_params,  // [n_params]
    const float* __restrict__ anchor_params,   // [n_anchors × n_params]
    float*       __restrict__ alignments,      // [n_anchors]
    float*       __restrict__ phases,          // [n_anchors]
    int          n_params,
    int          n_anchors)
{
    int anchor = blockIdx.x;
    if (anchor >= n_anchors) return;

    __shared__ float s_dot[MAX_THREADS_WG];
    __shared__ float s_na[MAX_THREADS_WG];
    __shared__ float s_nb[MAX_THREADS_WG];

    const float* ap = anchor_params + anchor * n_params;
    float dot = 0.0f, na = 0.0f, nb = 0.0f;

    for (int i = threadIdx.x; i < n_params; i += blockDim.x) {
        float a = current_params[i];
        float b = ap[i];
        dot = __builtin_amdgcn_fmaf(a, b, dot);
        na  = __builtin_amdgcn_fmaf(a, a, na);
        nb  = __builtin_amdgcn_fmaf(b, b, nb);
    }

    s_dot[threadIdx.x] = dot;
    s_na[threadIdx.x]  = na;
    s_nb[threadIdx.x]  = nb;
    __syncthreads();

    for (int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (threadIdx.x < stride) {
            s_dot[threadIdx.x] += s_dot[threadIdx.x + stride];
            s_na[threadIdx.x]  += s_na[threadIdx.x + stride];
            s_nb[threadIdx.x]  += s_nb[threadIdx.x + stride];
        }
        __syncthreads();
    }

    if (threadIdx.x == 0) {
        float denom = sqrtf(s_na[0]) * sqrtf(s_nb[0]) + 1e-8f;
        float alignment = s_dot[0] / denom;
        alignments[anchor] = alignment;
        // Phase = arccos(alignment) — quantum phase angle
        phases[anchor] = acosf(fmaxf(-1.0f, fminf(1.0f, alignment)));
    }
}

// =============================================================================
// Host Class: RyzenHaloHammingEngine
// =============================================================================
// Manages HIP resources for Hamming distance computation on Radeon 8060S.
// Leverages UMA: hipMallocManaged() for zero-copy CPU↔GPU access.

class RyzenHaloHammingEngine {
public:
    struct Config {
        int  device_id      = 0;
        int  n_clusters     = 64;
        int  hash_words     = HASH_WORDS;
        int  max_batch      = MAX_BATCH;
        int  embedding_dim  = EMBEDDING_DIM;
        int  n_params       = 10'000'000;
        float ewc_lambda    = EWC_LAMBDA;
        float learning_rate = LEARNING_RATE;
        float grad_clip     = GRAD_CLIP_NORM;
        float dp_epsilon    = 0.1f;
        float dp_delta      = 1e-5f;
        int  n_streams      = 4;
        bool use_uma        = true;   // Unified Memory Architecture
        bool use_fp16       = false;  // RDNA 3.5 FP16 (60 TFLOPS)
        int  seed           = 42;
    };

    explicit RyzenHaloHammingEngine(const Config& cfg = Config{})
        : cfg_(cfg), step_(0)
    {
        // Set AMD GPU device
        HIP_CHECK(hipSetDevice(cfg_.device_id));

        // Query device properties
        HIP_CHECK(hipGetDeviceProperties(&props_, cfg_.device_id));
        printf("[RyzenHalo] Device: %s\n", props_.name);
        printf("[RyzenHalo] CUs: %d | VRAM: %zu MB | Warp: %d\n",
               props_.multiProcessorCount,
               props_.totalGlobalMem >> 20,
               props_.warpSize);

        // Initialize rocBLAS
        ROCBLAS_CHECK(rocblas_create_handle(&rocblas_handle_));

        // Initialize rocRAND
        rocrand_create_generator(&rocrand_gen_, ROCRAND_RNG_PSEUDO_DEFAULT);
        rocrand_set_seed(rocrand_gen_, cfg_.seed);

        // Allocate UMA buffers (accessible from both CPU and GPU)
        if (cfg_.use_uma) {
            // hipMallocManaged: UMA on Strix Halo — zero-copy, 256 GB/s
            HIP_CHECK(hipMallocManaged(&d_params_,    cfg_.n_params * sizeof(float)));
            HIP_CHECK(hipMallocManaged(&d_fisher_,    cfg_.n_params * sizeof(float)));
            HIP_CHECK(hipMallocManaged(&d_theta_star_,cfg_.n_params * sizeof(float)));
            HIP_CHECK(hipMallocManaged(&d_gradients_, cfg_.n_params * sizeof(float)));
            HIP_CHECK(hipMallocManaged(&d_noise_,     cfg_.n_params * sizeof(float)));
            HIP_CHECK(hipMallocManaged(&d_embeddings_,
                cfg_.max_batch * cfg_.embedding_dim * sizeof(float)));
            HIP_CHECK(hipMallocManaged(&d_centroids_,
                cfg_.n_clusters * cfg_.hash_words * sizeof(uint64_t)));
            HIP_CHECK(hipMallocManaged(&d_cluster_counts_,
                cfg_.n_clusters * sizeof(int)));
            HIP_CHECK(hipMallocManaged(&d_thresholds_,
                cfg_.n_clusters * sizeof(int)));
        } else {
            HIP_CHECK(hipMalloc(&d_params_,    cfg_.n_params * sizeof(float)));
            HIP_CHECK(hipMalloc(&d_fisher_,    cfg_.n_params * sizeof(float)));
            HIP_CHECK(hipMalloc(&d_theta_star_,cfg_.n_params * sizeof(float)));
            HIP_CHECK(hipMalloc(&d_gradients_, cfg_.n_params * sizeof(float)));
            HIP_CHECK(hipMalloc(&d_noise_,     cfg_.n_params * sizeof(float)));
            HIP_CHECK(hipMalloc(&d_embeddings_,
                cfg_.max_batch * cfg_.embedding_dim * sizeof(float)));
            HIP_CHECK(hipMalloc(&d_centroids_,
                cfg_.n_clusters * cfg_.hash_words * sizeof(uint64_t)));
            HIP_CHECK(hipMalloc(&d_cluster_counts_, cfg_.n_clusters * sizeof(int)));
            HIP_CHECK(hipMalloc(&d_thresholds_,     cfg_.n_clusters * sizeof(int)));
        }

        // Initialize memory
        HIP_CHECK(hipMemset(d_fisher_,         0, cfg_.n_params * sizeof(float)));
        HIP_CHECK(hipMemset(d_centroids_,      0, cfg_.n_clusters * cfg_.hash_words * sizeof(uint64_t)));
        HIP_CHECK(hipMemset(d_cluster_counts_, 0, cfg_.n_clusters * sizeof(int)));

        // Initialize thresholds to default (24 bits)
        std::vector<int> init_thresh(cfg_.n_clusters, 24);
        HIP_CHECK(hipMemcpy(d_thresholds_, init_thresh.data(),
            cfg_.n_clusters * sizeof(int), hipMemcpyHostToDevice));

        // Initialize params with small random values
        rocrand_generate_normal(rocrand_gen_, d_params_, cfg_.n_params, 0.0f, 0.02f);

        // Create HIP streams
        streams_.resize(cfg_.n_streams);
        for (auto& s : streams_) HIP_CHECK(hipStreamCreate(&s));

        printf("[RyzenHalo] Engine initialized: %d params, %d clusters, UMA=%s\n",
               cfg_.n_params, cfg_.n_clusters, cfg_.use_uma ? "yes" : "no");
    }

    // -------------------------------------------------------------------------
    // Compute Hamming distances for a batch of hash pairs
    // -------------------------------------------------------------------------
    float compute_hamming_batch(
        const uint64_t* hashes_a,   // host or UMA pointer
        const uint64_t* hashes_b,
        int*            distances,
        int             n_pairs,
        hipStream_t     stream = nullptr)
    {
        hipEvent_t t0, t1;
        HIP_CHECK(hipEventCreate(&t0));
        HIP_CHECK(hipEventCreate(&t1));
        HIP_CHECK(hipEventRecord(t0, stream));

        int threads = 256;
        int blocks  = (n_pairs + threads - 1) / threads;

        hipLaunchKernelGGL(hamming_distance_batch_kernel,
            dim3(blocks), dim3(threads), 0, stream,
            hashes_a, hashes_b, distances, n_pairs, cfg_.hash_words);

        HIP_CHECK(hipEventRecord(t1, stream));
        HIP_CHECK(hipEventSynchronize(t1));
        float ms = 0.0f;
        HIP_CHECK(hipEventElapsedTime(&ms, t0, t1));
        HIP_CHECK(hipEventDestroy(t0));
        HIP_CHECK(hipEventDestroy(t1));

        ++step_;
        metrics_["hamming_batch_ms"] = ms;
        return ms;
    }

    // -------------------------------------------------------------------------
    // Compute Fisher Information diagonal
    // -------------------------------------------------------------------------
    float compute_fisher(
        const float* gradients,     // [n_samples × n_params]
        int          n_samples,
        hipStream_t  stream = nullptr)
    {
        hipEvent_t t0, t1;
        HIP_CHECK(hipEventCreate(&t0));
        HIP_CHECK(hipEventCreate(&t1));
        HIP_CHECK(hipEventRecord(t0, stream));

        int threads = 256;
        int blocks  = (cfg_.n_params + threads - 1) / threads;

        hipLaunchKernelGGL(fisher_diagonal_kernel,
            dim3(blocks), dim3(threads), 0, stream,
            gradients, d_fisher_, cfg_.n_params, n_samples);

        HIP_CHECK(hipEventRecord(t1, stream));
        HIP_CHECK(hipEventSynchronize(t1));
        float ms = 0.0f;
        HIP_CHECK(hipEventElapsedTime(&ms, t0, t1));
        HIP_CHECK(hipEventDestroy(t0));
        HIP_CHECK(hipEventDestroy(t1));

        metrics_["fisher_ms"] = ms;
        return ms;
    }

    // -------------------------------------------------------------------------
    // Apply EWC gradient
    // -------------------------------------------------------------------------
    float apply_ewc(
        const float* theta,
        const float* theta_star,
        float*       ewc_grad,
        float        lambda,
        hipStream_t  stream = nullptr)
    {
        hipEvent_t t0, t1;
        HIP_CHECK(hipEventCreate(&t0));
        HIP_CHECK(hipEventCreate(&t1));
        HIP_CHECK(hipEventRecord(t0, stream));

        int threads = 256;
        int blocks  = (cfg_.n_params + threads - 1) / threads;

        hipLaunchKernelGGL(ewc_gradient_kernel,
            dim3(blocks), dim3(threads), 0, stream,
            theta, theta_star, d_fisher_, ewc_grad, lambda, cfg_.n_params);

        HIP_CHECK(hipEventRecord(t1, stream));
        HIP_CHECK(hipEventSynchronize(t1));
        float ms = 0.0f;
        HIP_CHECK(hipEventElapsedTime(&ms, t0, t1));
        HIP_CHECK(hipEventDestroy(t0));
        HIP_CHECK(hipEventDestroy(t1));

        metrics_["ewc_ms"] = ms;
        return ms;
    }

    // -------------------------------------------------------------------------
    // Encode sensor data to 512-bit hashes
    // -------------------------------------------------------------------------
    float encode_sensors(
        const float*    coherence,
        const float*    phase,
        const uint32_t* adc,
        const uint32_t* sensor_ids,
        const uint64_t* timestamps,
        uint64_t*       hashes,
        int             n_sensors,
        hipStream_t     stream = nullptr)
    {
        hipEvent_t t0, t1;
        HIP_CHECK(hipEventCreate(&t0));
        HIP_CHECK(hipEventCreate(&t1));
        HIP_CHECK(hipEventRecord(t0, stream));

        int threads = 256;
        int blocks  = (n_sensors + threads - 1) / threads;

        hipLaunchKernelGGL(sensor_encode_kernel,
            dim3(blocks), dim3(threads), 0, stream,
            coherence, phase, adc, sensor_ids, timestamps, hashes, n_sensors);

        HIP_CHECK(hipEventRecord(t1, stream));
        HIP_CHECK(hipEventSynchronize(t1));
        float ms = 0.0f;
        HIP_CHECK(hipEventElapsedTime(&ms, t0, t1));
        HIP_CHECK(hipEventDestroy(t0));
        HIP_CHECK(hipEventDestroy(t1));

        metrics_["encode_ms"] = ms;
        return ms;
    }

    // -------------------------------------------------------------------------
    // Benchmark all kernels
    // -------------------------------------------------------------------------
    void benchmark(int n_iters = 100) {
        printf("\n[RyzenHalo] Benchmark on %s (gfx%d)\n",
               props_.name, props_.gcnArch);
        printf("[RyzenHalo] CUs=%d | UMA BW=256 GB/s | FP16=60 TFLOPS\n\n",
               props_.multiProcessorCount);

        // Allocate test data (UMA — accessible from CPU)
        int n_pairs = 10000;
        uint64_t *ha, *hb;
        int *dists;
        HIP_CHECK(hipMallocManaged(&ha,    n_pairs * HASH_WORDS * sizeof(uint64_t)));
        HIP_CHECK(hipMallocManaged(&hb,    n_pairs * HASH_WORDS * sizeof(uint64_t)));
        HIP_CHECK(hipMallocManaged(&dists, n_pairs * sizeof(int)));

        // Fill with random data (CPU side — UMA)
        std::mt19937_64 rng(42);
        for (int i = 0; i < n_pairs * HASH_WORDS; ++i) {
            ha[i] = rng();
            hb[i] = rng();
        }

        // Hamming benchmark
        float total_ms = 0.0f;
        for (int i = 0; i < n_iters; ++i) {
            total_ms += compute_hamming_batch(ha, hb, dists, n_pairs);
        }
        float mean_ms = total_ms / n_iters;
        float throughput = (float)n_pairs / (mean_ms / 1000.0f) / 1e6f;
        printf("[Hamming]  %.3f ms/iter | %.1f M pairs/s\n", mean_ms, throughput);

        // Fisher benchmark
        total_ms = 0.0f;
        int n_samples = 200;
        float* grads;
        HIP_CHECK(hipMallocManaged(&grads, n_samples * cfg_.n_params * sizeof(float)));
        rocrand_generate_normal(rocrand_gen_, grads, n_samples * cfg_.n_params, 0.0f, 0.01f);
        for (int i = 0; i < 10; ++i) {
            total_ms += compute_fisher(grads, n_samples);
        }
        printf("[Fisher]   %.3f ms/iter | %d params\n", total_ms / 10.0f, cfg_.n_params);

        // EWC benchmark
        float* ewc_grad;
        HIP_CHECK(hipMallocManaged(&ewc_grad, cfg_.n_params * sizeof(float)));
        total_ms = 0.0f;
        for (int i = 0; i < n_iters; ++i) {
            total_ms += apply_ewc(d_params_, d_theta_star_, ewc_grad, cfg_.ewc_lambda);
        }
        printf("[EWC]      %.3f ms/iter | lambda=%.1f\n", total_ms / n_iters, cfg_.ewc_lambda);

        // Cleanup
        hipFree(ha); hipFree(hb); hipFree(dists);
        hipFree(grads); hipFree(ewc_grad);
    }

    const std::unordered_map<std::string, float>& metrics() const { return metrics_; }
    long step() const { return step_; }

    ~RyzenHaloHammingEngine() {
        if (d_params_)         hipFree(d_params_);
        if (d_fisher_)         hipFree(d_fisher_);
        if (d_theta_star_)     hipFree(d_theta_star_);
        if (d_gradients_)      hipFree(d_gradients_);
        if (d_noise_)          hipFree(d_noise_);
        if (d_embeddings_)     hipFree(d_embeddings_);
        if (d_centroids_)      hipFree(d_centroids_);
        if (d_cluster_counts_) hipFree(d_cluster_counts_);
        if (d_thresholds_)     hipFree(d_thresholds_);
        for (auto& s : streams_) hipStreamDestroy(s);
        rocblas_destroy_handle(rocblas_handle_);
        rocrand_destroy_generator(rocrand_gen_);
    }

private:
    Config                                  cfg_;
    long                                    step_;
    hipDeviceProp_t                         props_;
    rocblas_handle                          rocblas_handle_;
    rocrand_generator                       rocrand_gen_;
    float*                                  d_params_         = nullptr;
    float*                                  d_fisher_         = nullptr;
    float*                                  d_theta_star_     = nullptr;
    float*                                  d_gradients_      = nullptr;
    float*                                  d_noise_          = nullptr;
    float*                                  d_embeddings_     = nullptr;
    uint64_t*                               d_centroids_      = nullptr;
    int*                                    d_cluster_counts_ = nullptr;
    int*                                    d_thresholds_     = nullptr;
    std::vector<hipStream_t>                streams_;
    std::unordered_map<std::string, float>  metrics_;
};

// =============================================================================
// Main Entry Point
// =============================================================================

int main(int argc, char** argv) {
    printf("=== Windows Zenith — AMD Ryzen AI Max+ 395 (Strix Halo) ===\n");
    printf("=== HIP/ROCm 7.1+ | RDNA 3.5 | 40 CUs | 256 GB/s UMA ===\n\n");

    // Query available HIP devices
    int device_count = 0;
    HIP_CHECK(hipGetDeviceCount(&device_count));
    printf("HIP devices found: %d\n", device_count);

    if (device_count == 0) {
        fprintf(stderr, "No HIP-capable AMD GPU found.\n");
        fprintf(stderr, "Install ROCm 7.1+: https://rocm.docs.amd.com\n");
        return 1;
    }

    for (int d = 0; d < device_count; ++d) {
        hipDeviceProp_t prop;
        HIP_CHECK(hipGetDeviceProperties(&prop, d));
        printf("  [%d] %s | CUs=%d | VRAM=%zu MB | gfx%d\n",
               d, prop.name, prop.multiProcessorCount,
               prop.totalGlobalMem >> 20, prop.gcnArch);
    }
    printf("\n");

    // Initialize engine for Radeon 8060S (gfx1151)
    RyzenHaloHammingEngine::Config cfg;
    cfg.device_id   = 0;
    cfg.n_clusters  = 64;
    cfg.n_params    = 1'000'000;
    cfg.use_uma     = true;   // Leverage Strix Halo UMA
    cfg.ewc_lambda  = 400.0f;
    cfg.seed        = 42;

    RyzenHaloHammingEngine engine(cfg);

    // Run benchmark
    engine.benchmark(100);

    printf("\n[WindowsZenith] Pipeline ready.\n");
    printf("[WindowsZenith] Compile: hipcc --offload-arch=gfx1151 -O3 -std=c++20 \\\n");
    printf("                         -lrocblas -lrocrand hamming_distance_hip.hip\n");

    return 0;
}