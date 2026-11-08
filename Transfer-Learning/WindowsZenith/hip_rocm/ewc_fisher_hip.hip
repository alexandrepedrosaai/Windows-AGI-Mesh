// =============================================================================
// ewc_fisher_hip.hip
// AMD HIP/ROCm — EWC Fisher Information + Gradient Compression
// Target: AMD Radeon 8060S (RDNA 3.5, gfx1151) — Ryzen AI Max+ 395
// Compile: hipcc --offload-arch=gfx1151 -O3 -std=c++20 -lrocblas -lrocrand
// ROCm 7.1+ | UMA 256 GB/s | FP16 60 TFLOPS | INT8 120 TOPS
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
#include <span>

namespace cg = cooperative_groups;

// =============================================================================
// HIP Error Macros
// =============================================================================

#define HIP_CHECK(call) \
    do { hipError_t e=(call); if(e!=hipSuccess){ \
        fprintf(stderr,"[HIP] %s:%d %s\n",__FILE__,__LINE__,hipGetErrorString(e)); \
        std::abort(); } } while(0)

#define ROCBLAS_CHECK(call) \
    do { rocblas_status s=(call); if(s!=rocblas_status_success){ \
        fprintf(stderr,"[rocBLAS] %s:%d status=%d\n",__FILE__,__LINE__,(int)s); \
        std::abort(); } } while(0)

// =============================================================================
// RDNA 3.5 Constants (Radeon 8060S / gfx1151)
// =============================================================================

constexpr int  WAVEFRONT       = 32;      // Wave32 (RDNA default)
constexpr int  MAX_WG_SIZE     = 1024;    // Max workgroup size
constexpr int  LDS_BYTES       = 65536;   // 64 KB LDS per CU
constexpr int  N_CUS           = 40;      // Compute Units
constexpr int  TILE            = 32;      // Tile size for GEMM
constexpr int  N_PARAMS_DEF    = 10000000;
constexpr float EWC_LAM_DEF    = 400.0f;
constexpr float LR_DEF         = 0.001f;
constexpr float CLIP_DEF       = 5.0f;
constexpr float DP_EPS_DEF     = 0.1f;
constexpr float DP_DELTA_DEF   = 1e-5f;

// =============================================================================
// KERNEL 0: Online Fisher Update (EMA)
// =============================================================================
// F_i = (1-alpha)*F_i + alpha*g_i^2
// RDNA 3.5: v_fma_f32 (fused multiply-add, 1 cycle)

__global__ void fisher_online_update_kernel(
    float*       __restrict__ fisher,       // [n_params] — in/out
    const float* __restrict__ gradient,     // [n_params]
    float        alpha,
    int          n_params)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_params) return;

    float g   = gradient[pid];
    float g2  = g * g;
    float old = fisher[pid];
    // EMA: F = (1-alpha)*F + alpha*g^2
    fisher[pid] = __builtin_amdgcn_fmaf(alpha, g2,
                  __builtin_amdgcn_fmaf(-alpha, old, old));
}

// =============================================================================
// KERNEL 1: Fisher Normalization
// =============================================================================
// Normalizes Fisher diagonal by its maximum value.
// Uses two-pass reduction: first find max, then divide.

__global__ void fisher_normalize_kernel(
    float*       __restrict__ fisher,       // [n_params] — in/out
    const float* __restrict__ fisher_max,   // [1] pre-computed max
    float        epsilon,
    int          n_params)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_params) return;

    float max_val = *fisher_max;
    if (max_val > epsilon) {
        fisher[pid] /= max_val;
    }
}

// =============================================================================
// KERNEL 2: Fisher Max Reduction (Wave32 optimized)
// =============================================================================

__global__ void fisher_max_kernel(
    const float* __restrict__ fisher,       // [n_params]
    float*       __restrict__ max_out,      // [1]
    int          n_params)
{
    __shared__ float s_max[MAX_WG_SIZE];

    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    float local_max = 0.0f;

    while (pid < n_params) {
        local_max = fmaxf(local_max, fisher[pid]);
        pid += gridDim.x * blockDim.x;
    }

    s_max[threadIdx.x] = local_max;
    __syncthreads();

    // LDS reduction
    for (int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (threadIdx.x < stride)
            s_max[threadIdx.x] = fmaxf(s_max[threadIdx.x], s_max[threadIdx.x + stride]);
        __syncthreads();
    }

    if (threadIdx.x == 0) {
        atomicMax((int*)max_out, __float_as_int(s_max[0]));
    }
}

// =============================================================================
// KERNEL 3: Fisher L2 Norm (for transport on Stream 5)
// =============================================================================

__global__ void fisher_l2_norm_kernel(
    const float* __restrict__ fisher,       // [n_params]
    float*       __restrict__ norm_out,     // [1]
    int          n_params)
{
    __shared__ float s_sum[MAX_WG_SIZE];

    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    float local_sum = 0.0f;

    while (pid < n_params) {
        float f = fisher[pid];
        local_sum = __builtin_amdgcn_fmaf(f, f, local_sum);
        pid += gridDim.x * blockDim.x;
    }

    s_sum[threadIdx.x] = local_sum;
    __syncthreads();

    for (int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (threadIdx.x < stride)
            s_sum[threadIdx.x] += s_sum[threadIdx.x + stride];
        __syncthreads();
    }

    if (threadIdx.x == 0) {
        atomicAdd(norm_out, s_sum[0]);
    }
}

// =============================================================================
// KERNEL 4: EWC Full Gradient (task + EWC combined)
// =============================================================================
// grad_total_i = task_grad_i + lambda * F_i * (theta_i - theta*_i)
// Fused kernel: avoids extra memory round-trip.

__global__ void ewc_full_gradient_kernel(
    const float* __restrict__ task_grad,    // [n_params]
    const float* __restrict__ theta,        // [n_params]
    const float* __restrict__ theta_star,   // [n_params]
    const float* __restrict__ fisher,       // [n_params]
    float*       __restrict__ total_grad,   // [n_params]
    float        lambda,
    float        clip_norm,
    int          n_params)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_params) return;

    float delta    = theta[pid] - theta_star[pid];
    float ewc_g    = lambda * fisher[pid] * delta;
    float total    = task_grad[pid] + ewc_g;

    // Gradient clipping (element-wise)
    float abs_total = fabsf(total);
    if (abs_total > clip_norm) {
        total = total * (clip_norm / abs_total);
    }

    total_grad[pid] = total;
}

// =============================================================================
// KERNEL 5: Multi-Task EWC (sum over all previous tasks)
// =============================================================================
// L_ewc = sum_k [ gamma^(T-k) * (lambda/2) * sum_i(F_k_i * (theta_i - theta*_k_i)^2) ]

__global__ void ewc_multitask_gradient_kernel(
    const float* __restrict__ theta,            // [n_params]
    const float* __restrict__ all_theta_star,   // [n_tasks × n_params]
    const float* __restrict__ all_fisher,       // [n_tasks × n_params]
    float*       __restrict__ ewc_grad,         // [n_params]
    float        lambda,
    float        gamma,
    int          n_tasks,
    int          n_params)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_params) return;

    float grad_sum = 0.0f;
    float theta_i  = theta[pid];

    for (int t = 0; t < n_tasks; ++t) {
        // gamma^(n_tasks - t - 1): older tasks get less weight
        float task_gamma = powf(gamma, (float)(n_tasks - t - 1));
        float ts_i = all_theta_star[t * n_params + pid];
        float f_i  = all_fisher[t * n_params + pid];
        float delta = theta_i - ts_i;
        grad_sum = __builtin_amdgcn_fmaf(task_gamma * lambda * f_i, delta, grad_sum);
    }

    ewc_grad[pid] = grad_sum;
}

// =============================================================================
// KERNEL 6: Gradient Top-K Threshold Finder (parallel histogram)
// =============================================================================
// Finds the K-th largest absolute gradient value using histogram.
// RDNA 3.5: atomicAdd on LDS (ds_add_u32) is very fast.

__global__ void topk_threshold_kernel(
    const float* __restrict__ gradients,    // [n_params]
    int*         __restrict__ histogram,    // [256] bins
    float*       __restrict__ max_abs,      // [1] max |gradient|
    int          n_params)
{
    __shared__ int s_hist[256];
    __shared__ float s_max;

    // Initialize LDS histogram
    if (threadIdx.x < 256) s_hist[threadIdx.x] = 0;
    if (threadIdx.x == 0) s_max = 0.0f;
    __syncthreads();

    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    float local_max = 0.0f;

    while (pid < n_params) {
        float abs_g = fabsf(gradients[pid]);
        local_max = fmaxf(local_max, abs_g);
        pid += gridDim.x * blockDim.x;
    }

    // Wave32 max reduction
    for (int offset = WAVEFRONT / 2; offset > 0; offset >>= 1)
        local_max = fmaxf(local_max, __shfl_down(local_max, offset));

    if (threadIdx.x % WAVEFRONT == 0)
        atomicMax((int*)&s_max, __float_as_int(local_max));
    __syncthreads();

    // Build histogram
    pid = blockIdx.x * blockDim.x + threadIdx.x;
    while (pid < n_params) {
        float abs_g = fabsf(gradients[pid]);
        if (s_max > 1e-8f) {
            int bin = (int)(abs_g / s_max * 255.0f);
            bin = min(255, max(0, bin));
            atomicAdd(&s_hist[bin], 1);
        }
        pid += gridDim.x * blockDim.x;
    }
    __syncthreads();

    // Merge LDS histogram to global
    if (threadIdx.x < 256) {
        atomicAdd(&histogram[threadIdx.x], s_hist[threadIdx.x]);
    }
    if (threadIdx.x == 0) {
        atomicMax((int*)max_abs, __float_as_int(s_max));
    }
}

// =============================================================================
// KERNEL 7: Gradient Compression — 4-bit Quantization
// =============================================================================
// Packs 2 INT4 values per byte for 8× compression ratio.
// RDNA 3.5: v_bfe_u32 (bit field extract) for nibble operations.

__global__ void quantize_int4_kernel(
    const float*  __restrict__ gradients,   // [n_params] FP32
    uint8_t*      __restrict__ packed,      // [n_params/2] INT4 packed
    float*        __restrict__ scale,       // [1]
    int           n_params)
{
    __shared__ float s_max[MAX_WG_SIZE];

    // Find max absolute value
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
        *scale = max_val / 7.0f;  // INT4 range: [-7, 7]
    }
    __syncthreads();

    float sc = max_val / 7.0f + 1e-8f;

    // Pack two INT4 values per byte
    pid = (blockIdx.x * blockDim.x + threadIdx.x) * 2;
    while (pid + 1 < n_params) {
        float g0 = gradients[pid];
        float g1 = gradients[pid + 1];

        int q0 = max(-7, min(7, (int)roundf(g0 / sc)));
        int q1 = max(-7, min(7, (int)roundf(g1 / sc)));

        // Pack: low nibble = q0, high nibble = q1
        uint8_t byte = (uint8_t)((q0 & 0x0F) | ((q1 & 0x0F) << 4));
        packed[pid / 2] = byte;

        pid += gridDim.x * blockDim.x * 2;
    }
}

// =============================================================================
// KERNEL 8: Gradient Dequantization — 4-bit
// =============================================================================

__global__ void dequantize_int4_kernel(
    const uint8_t* __restrict__ packed,     // [n_params/2]
    float*         __restrict__ gradients,  // [n_params]
    float          scale,
    int            n_params)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx * 2 >= n_params) return;

    uint8_t byte = packed[idx];

    // Extract nibbles with sign extension
    int q0 = (int)(byte & 0x0F);
    int q1 = (int)((byte >> 4) & 0x0F);

    // Sign extend from 4 bits
    if (q0 & 0x08) q0 |= 0xFFFFFFF0;
    if (q1 & 0x08) q1 |= 0xFFFFFFF0;

    gradients[idx * 2]     = (float)q0 * scale;
    if (idx * 2 + 1 < n_params)
        gradients[idx * 2 + 1] = (float)q1 * scale;
}

// =============================================================================
// KERNEL 9: Error Feedback for Gradient Compression
// =============================================================================
// error = original_grad - reconstructed_grad
// Next round: corrected_grad = grad + error

__global__ void error_feedback_kernel(
    const float* __restrict__ original,     // [n_params]
    const float* __restrict__ reconstructed,// [n_params]
    float*       __restrict__ error,        // [n_params] — in/out
    int          n_params)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_params) return;

    // error = original - reconstructed (accumulate)
    error[pid] += original[pid] - reconstructed[pid];
}

// =============================================================================
// KERNEL 10: Importance Sampling Weights (PER)
// =============================================================================
// w_i = (1 / (N * P(i)))^beta, normalized by max weight.

__global__ void importance_weights_kernel(
    const float* __restrict__ priorities,   // [buffer_size]
    float*       __restrict__ weights,      // [n_sample]
    const int*   __restrict__ indices,      // [n_sample]
    float        total_priority,
    float        beta,
    int          n_sample,
    int          buffer_size)
{
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= n_sample) return;

    int idx = indices[tid];
    float prob = priorities[idx] / total_priority;
    float w = powf(1.0f / ((float)buffer_size * prob + 1e-8f), beta);
    weights[tid] = w;
}

// =============================================================================
// KERNEL 11: Softmax (for attention and replay sampling)
// =============================================================================
// Numerically stable softmax using max subtraction.
// RDNA 3.5: uses LDS for max and sum reductions.

__global__ void softmax_kernel(
    float*       __restrict__ x,            // [batch × seq] — in/out
    int          batch_size,
    int          seq_len)
{
    int bid = blockIdx.x;
    if (bid >= batch_size) return;

    float* row = x + bid * seq_len;
    __shared__ float s_max;
    __shared__ float s_sum;

    // Find max
    float local_max = -1e38f;
    for (int i = threadIdx.x; i < seq_len; i += blockDim.x)
        local_max = fmaxf(local_max, row[i]);

    for (int offset = WAVEFRONT / 2; offset > 0; offset >>= 1)
        local_max = fmaxf(local_max, __shfl_down(local_max, offset));

    if (threadIdx.x % WAVEFRONT == 0)
        atomicMax((int*)&s_max, __float_as_int(local_max));
    __syncthreads();

    // Compute exp(x - max) and sum
    float local_sum = 0.0f;
    for (int i = threadIdx.x; i < seq_len; i += blockDim.x) {
        float e = expf(row[i] - s_max);
        row[i] = e;
        local_sum += e;
    }

    for (int offset = WAVEFRONT / 2; offset > 0; offset >>= 1)
        local_sum += __shfl_down(local_sum, offset);

    if (threadIdx.x % WAVEFRONT == 0)
        atomicAdd(&s_sum, local_sum);
    __syncthreads();

    // Normalize
    float inv_sum = 1.0f / (s_sum + 1e-8f);
    for (int i = threadIdx.x; i < seq_len; i += blockDim.x)
        row[i] *= inv_sum;
}

// =============================================================================
// KERNEL 12: Layer Normalization (Transformer)
// =============================================================================
// y = (x - mean) / sqrt(var + eps) * gamma + beta
// RDNA 3.5: uses LDS for mean and variance reductions.

__global__ void layer_norm_kernel(
    const float* __restrict__ x,            // [batch × dim]
    const float* __restrict__ gamma,        // [dim]
    const float* __restrict__ beta,         // [dim]
    float*       __restrict__ y,            // [batch × dim]
    float        eps,
    int          batch_size,
    int          dim)
{
    int bid = blockIdx.x;
    if (bid >= batch_size) return;

    const float* xrow = x + bid * dim;
    float*       yrow = y + bid * dim;

    __shared__ float s_mean;
    __shared__ float s_var;

    // Compute mean
    float local_sum = 0.0f;
    for (int i = threadIdx.x; i < dim; i += blockDim.x)
        local_sum += xrow[i];

    for (int offset = WAVEFRONT / 2; offset > 0; offset >>= 1)
        local_sum += __shfl_down(local_sum, offset);

    if (threadIdx.x % WAVEFRONT == 0)
        atomicAdd(&s_mean, local_sum);
    __syncthreads();

    float mean = s_mean / (float)dim;

    // Compute variance
    float local_var = 0.0f;
    for (int i = threadIdx.x; i < dim; i += blockDim.x) {
        float diff = xrow[i] - mean;
        local_var = __builtin_amdgcn_fmaf(diff, diff, local_var);
    }

    for (int offset = WAVEFRONT / 2; offset > 0; offset >>= 1)
        local_var += __shfl_down(local_var, offset);

    if (threadIdx.x % WAVEFRONT == 0)
        atomicAdd(&s_var, local_var);
    __syncthreads();

    float inv_std = rsqrtf(s_var / (float)dim + eps);

    // Normalize and scale
    for (int i = threadIdx.x; i < dim; i += blockDim.x) {
        yrow[i] = (xrow[i] - mean) * inv_std * gamma[i] + beta[i];
    }
}

// =============================================================================
// KERNEL 13: GELU Activation (Transformer FFN)
// =============================================================================
// GELU(x) = 0.5 * x * (1 + tanh(sqrt(2/pi) * (x + 0.044715 * x^3)))
// RDNA 3.5: v_tanh_f32 (native instruction on gfx1151)

__global__ void gelu_kernel(
    const float* __restrict__ x,            // [n]
    float*       __restrict__ y,            // [n]
    int          n)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n) return;

    float xi = x[pid];
    // Approximate GELU
    const float sqrt_2_over_pi = 0.7978845608f;
    const float coeff = 0.044715f;
    float inner = sqrt_2_over_pi * (xi + coeff * xi * xi * xi);
    y[pid] = 0.5f * xi * (1.0f + tanhf(inner));
}

// =============================================================================
// KERNEL 14: Stratified Replay Sampling
// =============================================================================
// Samples K experiences from replay buffer using stratified sampling.
// Ensures uniform coverage across priority distribution.

__global__ void stratified_sample_kernel(
    const float* __restrict__ probs,        // [buffer_size] normalized
    int*         __restrict__ selected,     // [K]
    const float* __restrict__ rand_vals,    // [K] uniform [0,1)
    int          buffer_size,
    int          K)
{
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= K) return;

    float segment = 1.0f / (float)K;
    float target  = ((float)tid + rand_vals[tid]) * segment;

    float cumsum = 0.0f;
    for (int i = 0; i < buffer_size; ++i) {
        cumsum += probs[i];
        if (cumsum >= target) {
            selected[tid] = i;
            return;
        }
    }
    selected[tid] = buffer_size - 1;
}

// =============================================================================
// KERNEL 15: Federated Gradient Aggregation (FedAvg)
// =============================================================================
// Aggregates gradients from N nodes: g_avg = (1/N) * sum_n(g_n)
// With optional differential privacy noise injection.

__global__ void fedavg_kernel(
    const float* __restrict__ all_gradients, // [n_nodes × n_params]
    float*       __restrict__ avg_gradient,  // [n_params]
    const float* __restrict__ dp_noise,      // [n_params] (optional)
    float        noise_std,
    int          n_nodes,
    int          n_params)
{
    int pid = blockIdx.x * blockDim.x + threadIdx.x;
    if (pid >= n_params) return;

    float sum = 0.0f;
    for (int n = 0; n < n_nodes; ++n) {
        sum += all_gradients[n * n_params + pid];
    }

    float avg = sum / (float)n_nodes;

    // Add DP noise if noise_std > 0
    if (noise_std > 0.0f && dp_noise != nullptr) {
        avg += noise_std * dp_noise[pid];
    }

    avg_gradient[pid] = avg;
}

// =============================================================================
// Host Class: EWCFisherEngine
// =============================================================================
// Manages EWC Fisher computation and gradient compression on Radeon 8060S.
// Uses UMA (hipMallocManaged) for zero-copy CPU↔GPU access.

class EWCFisherEngine {
public:
    struct Config {
        int   device_id    = 0;
        int   n_params     = N_PARAMS_DEF;
        int   n_tasks_max  = 10;
        float ewc_lambda   = EWC_LAM_DEF;
        float gamma        = 1.0f;         // Task decay factor
        float fisher_alpha = 0.1f;         // Online Fisher EMA rate
        float grad_clip    = CLIP_DEF;
        float dp_epsilon   = DP_EPS_DEF;
        float dp_delta     = DP_DELTA_DEF;
        float topk_ratio   = 0.1f;         // Keep top 10% gradients
        bool  use_uma      = true;
        bool  use_int4     = false;        // 4-bit quantization
        int   n_streams    = 4;
        int   seed         = 42;
    };

    explicit EWCFisherEngine(const Config& cfg = Config{})
        : cfg_(cfg), step_(0), current_task_(0)
    {
        HIP_CHECK(hipSetDevice(cfg_.device_id));
        HIP_CHECK(hipGetDeviceProperties(&props_, cfg_.device_id));

        ROCBLAS_CHECK(rocblas_create_handle(&rocblas_));
        rocrand_create_generator(&rocrand_, ROCRAND_RNG_PSEUDO_DEFAULT);
        rocrand_set_seed(rocrand_, cfg_.seed);

        // Allocate UMA buffers
        auto alloc = [&](void** ptr, size_t bytes) {
            if (cfg_.use_uma)
                HIP_CHECK(hipMallocManaged(ptr, bytes));
            else
                HIP_CHECK(hipMalloc(ptr, bytes));
        };

        size_t param_bytes = cfg_.n_params * sizeof(float);
        alloc((void**)&d_fisher_,      param_bytes);
        alloc((void**)&d_theta_,       param_bytes);
        alloc((void**)&d_theta_star_,  param_bytes);
        alloc((void**)&d_task_grad_,   param_bytes);
        alloc((void**)&d_ewc_grad_,    param_bytes);
        alloc((void**)&d_total_grad_,  param_bytes);
        alloc((void**)&d_error_fb_,    param_bytes);
        alloc((void**)&d_noise_,       param_bytes);
        alloc((void**)&d_fisher_max_,  sizeof(float));
        alloc((void**)&d_fisher_norm_, sizeof(float));
        alloc((void**)&d_penalty_,     sizeof(float));

        // Multi-task storage
        size_t mt_bytes = cfg_.n_tasks_max * cfg_.n_params * sizeof(float);
        alloc((void**)&d_all_theta_star_, mt_bytes);
        alloc((void**)&d_all_fisher_,     mt_bytes);

        // Initialize
        HIP_CHECK(hipMemset(d_fisher_,     0, param_bytes));
        HIP_CHECK(hipMemset(d_error_fb_,   0, param_bytes));
        HIP_CHECK(hipMemset(d_all_fisher_, 0, mt_bytes));

        // Initialize theta with small random values
        rocrand_generate_normal(rocrand_, d_theta_, cfg_.n_params, 0.0f, 0.02f);

        // Create streams
        streams_.resize(cfg_.n_streams);
        for (auto& s : streams_) HIP_CHECK(hipStreamCreate(&s));

        printf("[EWCFisher] Init: %d params, %d tasks_max, UMA=%s\n",
               cfg_.n_params, cfg_.n_tasks_max, cfg_.use_uma ? "yes" : "no");
    }

    // -------------------------------------------------------------------------
    // Update Fisher online (EMA)
    // -------------------------------------------------------------------------
    float update_fisher_online(
        const float* gradient,
        hipStream_t  stream = nullptr)
    {
        hipEvent_t t0, t1;
        HIP_CHECK(hipEventCreate(&t0));
        HIP_CHECK(hipEventCreate(&t1));
        HIP_CHECK(hipEventRecord(t0, stream));

        int threads = 256;
        int blocks  = (cfg_.n_params + threads - 1) / threads;

        hipLaunchKernelGGL(fisher_online_update_kernel,
            dim3(blocks), dim3(threads), 0, stream,
            d_fisher_, gradient, cfg_.fisher_alpha, cfg_.n_params);

        HIP_CHECK(hipEventRecord(t1, stream));
        HIP_CHECK(hipEventSynchronize(t1));
        float ms = 0.0f;
        HIP_CHECK(hipEventElapsedTime(&ms, t0, t1));
        HIP_CHECK(hipEventDestroy(t0));
        HIP_CHECK(hipEventDestroy(t1));

        ++step_;
        metrics_["fisher_update_ms"] = ms;
        return ms;
    }

    // -------------------------------------------------------------------------
    // Compute EWC full gradient (task + EWC regularization)
    // -------------------------------------------------------------------------
    float compute_ewc_gradient(
        const float* task_grad,
        const float* theta,
        const float* theta_star,
        float*       total_grad,
        float        lambda,
        hipStream_t  stream = nullptr)
    {
        hipEvent_t t0, t1;
        HIP_CHECK(hipEventCreate(&t0));
        HIP_CHECK(hipEventCreate(&t1));
        HIP_CHECK(hipEventRecord(t0, stream));

        int threads = 256;
        int blocks  = (cfg_.n_params + threads - 1) / threads;

        hipLaunchKernelGGL(ewc_full_gradient_kernel,
            dim3(blocks), dim3(threads), 0, stream,
            task_grad, theta, theta_star, d_fisher_,
            total_grad, lambda, cfg_.grad_clip, cfg_.n_params);

        HIP_CHECK(hipEventRecord(t1, stream));
        HIP_CHECK(hipEventSynchronize(t1));
        float ms = 0.0f;
        HIP_CHECK(hipEventElapsedTime(&ms, t0, t1));
        HIP_CHECK(hipEventDestroy(t0));
        HIP_CHECK(hipEventDestroy(t1));

        metrics_["ewc_grad_ms"] = ms;
        return ms;
    }

    // -------------------------------------------------------------------------
    // On task boundary: save theta* and Fisher for current task
    // -------------------------------------------------------------------------
    void on_task_boundary(int new_task_id, hipStream_t stream = nullptr) {
        if (current_task_ < cfg_.n_tasks_max) {
            size_t offset = current_task_ * cfg_.n_params;
            // Save theta* for current task
            HIP_CHECK(hipMemcpyAsync(
                d_all_theta_star_ + offset, d_theta_,
                cfg_.n_params * sizeof(float),
                hipMemcpyDeviceToDevice, stream));
            // Save Fisher for current task
            HIP_CHECK(hipMemcpyAsync(
                d_all_fisher_ + offset, d_fisher_,
                cfg_.n_params * sizeof(float),
                hipMemcpyDeviceToDevice, stream));
        }
        current_task_ = new_task_id;
        // Reset Fisher for new task
        HIP_CHECK(hipMemsetAsync(d_fisher_, 0,
            cfg_.n_params * sizeof(float), stream));

        printf("[EWCFisher] Task boundary: %d → %d\n",
               current_task_ - 1, new_task_id);
    }

    // -------------------------------------------------------------------------
    // Compute Fisher L2 norm (for WebTransport Stream 5)
    // -------------------------------------------------------------------------
    float get_fisher_norm(hipStream_t stream = nullptr) {
        HIP_CHECK(hipMemset(d_fisher_norm_, 0, sizeof(float)));

        int threads = 256;
        int blocks  = min(256, (cfg_.n_params + threads - 1) / threads);

        hipLaunchKernelGGL(fisher_l2_norm_kernel,
            dim3(blocks), dim3(threads), 0, stream,
            d_fisher_, d_fisher_norm_, cfg_.n_params);

        HIP_CHECK(hipStreamSynchronize(stream ? stream : nullptr));

        float norm = 0.0f;
        HIP_CHECK(hipMemcpy(&norm, d_fisher_norm_, sizeof(float), hipMemcpyDeviceToHost));
        return sqrtf(norm);
    }

    // -------------------------------------------------------------------------
    // Compress gradients with error feedback
    // -------------------------------------------------------------------------
    float compress_gradients(
        float*   gradient,          // [n_params] — modified in place
        float*   sparse_vals,       // output sparse values
        int*     sparse_idx,        // output sparse indices
        int*     n_selected,        // output count
        hipStream_t stream = nullptr)
    {
        hipEvent_t t0, t1;
        HIP_CHECK(hipEventCreate(&t0));
        HIP_CHECK(hipEventCreate(&t1));
        HIP_CHECK(hipEventRecord(t0, stream));

        // Add error feedback
        int threads = 256;
        int blocks  = (cfg_.n_params + threads - 1) / threads;

        hipLaunchKernelGGL(error_feedback_kernel,
            dim3(blocks), dim3(threads), 0, stream,
            gradient, gradient, d_error_fb_, cfg_.n_params);

        // Find threshold (simplified: use fixed ratio)
        float threshold = 0.01f;  // In production: use histogram kernel

        // Apply Top-K sparsification
        HIP_CHECK(hipMemset(n_selected, 0, sizeof(int)));
        hipLaunchKernelGGL(topk_sparsify_kernel,
            dim3(blocks), dim3(threads), 0, stream,
            gradient, sparse_vals, sparse_idx,
            threshold, cfg_.n_params, n_selected);

        HIP_CHECK(hipEventRecord(t1, stream));
        HIP_CHECK(hipEventSynchronize(t1));
        float ms = 0.0f;
        HIP_CHECK(hipEventElapsedTime(&ms, t0, t1));
        HIP_CHECK(hipEventDestroy(t0));
        HIP_CHECK(hipEventDestroy(t1));

        metrics_["compress_ms"] = ms;
        return ms;
    }

    // -------------------------------------------------------------------------
    // Benchmark
    // -------------------------------------------------------------------------
    void benchmark(int n_iters = 100) {
        printf("\n[EWCFisher] Benchmark on %s\n", props_.name);

        // Fisher update benchmark
        float* grad;
        HIP_CHECK(hipMallocManaged(&grad, cfg_.n_params * sizeof(float)));
        rocrand_generate_normal(rocrand_, grad, cfg_.n_params, 0.0f, 0.01f);

        float total_ms = 0.0f;
        for (int i = 0; i < n_iters; ++i)
            total_ms += update_fisher_online(grad);
        printf("[Fisher Online] %.3f ms/iter | %d params\n",
               total_ms / n_iters, cfg_.n_params);

        // EWC gradient benchmark
        float* ewc_out;
        HIP_CHECK(hipMallocManaged(&ewc_out, cfg_.n_params * sizeof(float)));
        total_ms = 0.0f;
        for (int i = 0; i < n_iters; ++i)
            total_ms += compute_ewc_gradient(
                grad, d_theta_, d_theta_star_, ewc_out, cfg_.ewc_lambda);
        printf("[EWC Gradient] %.3f ms/iter | lambda=%.1f\n",
               total_ms / n_iters, cfg_.ewc_lambda);

        // Fisher norm
        float norm = get_fisher_norm();
        printf("[Fisher Norm]  %.4f\n", norm);

        hipFree(grad);
        hipFree(ewc_out);
    }

    const std::unordered_map<std::string, float>& metrics() const { return metrics_; }
    float* fisher() { return d_fisher_; }
    float* theta()  { return d_theta_; }
    int    task()   { return current_task_; }

    ~EWCFisherEngine() {
        auto free_ptr = [&](void* p) { if (p) hipFree(p); };
        free_ptr(d_fisher_);      free_ptr(d_theta_);
        free_ptr(d_theta_star_);  free_ptr(d_task_grad_);
        free_ptr(d_ewc_grad_);    free_ptr(d_total_grad_);
        free_ptr(d_error_fb_);    free_ptr(d_noise_);
        free_ptr(d_fisher_max_);  free_ptr(d_fisher_norm_);
        free_ptr(d_penalty_);     free_ptr(d_all_theta_star_);
        free_ptr(d_all_fisher_);
        for (auto& s : streams_) hipStreamDestroy(s);
        rocblas_destroy_handle(rocblas_);
        rocrand_destroy_generator(rocrand_);
    }

private:
    Config                                  cfg_;
    long                                    step_;
    int                                     current_task_;
    hipDeviceProp_t                         props_;
    rocblas_handle                          rocblas_;
    rocrand_generator                       rocrand_;
    float*                                  d_fisher_         = nullptr;
    float*                                  d_theta_          = nullptr;
    float*                                  d_theta_star_     = nullptr;
    float*                                  d_task_grad_      = nullptr;
    float*                                  d_ewc_grad_       = nullptr;
    float*                                  d_total_grad_     = nullptr;
    float*                                  d_error_fb_       = nullptr;
    float*                                  d_noise_          = nullptr;
    float*                                  d_fisher_max_     = nullptr;
    float*                                  d_fisher_norm_    = nullptr;
    float*                                  d_penalty_        = nullptr;
    float*                                  d_all_theta_star_ = nullptr;
    float*                                  d_all_fisher_     = nullptr;
    std::vector<hipStream_t>                streams_;
    std::unordered_map<std::string, float>  metrics_;
};

// =============================================================================
// Main
// =============================================================================

int main(int argc, char** argv) {
    printf("=== EWC Fisher Engine — AMD Ryzen AI Max+ 395 (Strix Halo) ===\n");
    printf("=== HIP/ROCm 7.1 | RDNA 3.5 gfx1151 | 256 GB/s UMA ===\n\n");

    int dc = 0;
    HIP_CHECK(hipGetDeviceCount(&dc));
    if (dc == 0) {
        fprintf(stderr, "No HIP device. Install ROCm 7.1+\n");
        return 1;
    }

    EWCFisherEngine::Config cfg;
    cfg.n_params   = 1'000'000;
    cfg.ewc_lambda = 400.0f;
    cfg.use_uma    = true;

    EWCFisherEngine engine(cfg);
    engine.benchmark(100);

    printf("\n[EWCFisher] Compile:\n");
    printf("  hipcc --offload-arch=gfx1151 -O3 -std=c++20 \\\n");
    printf("        -lrocblas -lrocrand ewc_fisher_hip.hip\n");

    return 0;
}
