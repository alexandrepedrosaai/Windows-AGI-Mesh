// =============================================================================
// webview2_transport.cu — C++/CUDA for Windows-AGI-Mesh
// Namespace: SiameseTwinAI_Windows
// Compile: nvcc -O3 -arch=sm_90 -std=c++20 -lcublas -lcurand webview2_transport.cu
// Linux:   g++ -O3 -std=c++20 -fopenmp -march=native -DLINUX_BUILD
// =============================================================================

#include <cuda_runtime.h>
#include <cuda_fp16.h>
#include <cublas_v2.h>
#include <curand.h>
#include <thrust/device_vector.h>
#include <thrust/host_vector.h>
#include <thrust/transform.h>
#include <thrust/reduce.h>
#include <thrust/sort.h>
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
#include <queue>
#include <optional>
#include <numeric>
#include <random>
#include <iostream>
#include <fstream>
#include <sstream>
#include <immintrin.h>
#include <omp.h>

#define CUDA_CHECK(call) do { cudaError_t e=(call); if(e!=cudaSuccess){ fprintf(stderr,"CUDA %s:%d %s\n",__FILE__,__LINE__,cudaGetErrorString(e)); std::abort(); } } while(0)
#define CUBLAS_CHECK(call) do { cublasStatus_t s=(call); if(s!=CUBLAS_STATUS_SUCCESS){ fprintf(stderr,"cuBLAS %s:%d %d\n",__FILE__,__LINE__,(int)s); std::abort(); } } while(0)
#define CURAND_CHECK(call) do { curandStatus_t s=(call); if(s!=CURAND_STATUS_SUCCESS){ fprintf(stderr,"cuRAND %s:%d %d\n",__FILE__,__LINE__,(int)s); std::abort(); } } while(0)

constexpr int WARP_SIZE = 32;
constexpr int MAX_THREADS = 1024;
constexpr int TILE = 32;
constexpr int EMB_DIM = 512;
constexpr int MAX_CLUSTERS = 64;
constexpr int REPLAY_BUF = 65536;
constexpr int MAX_BATCH = 512;
constexpr int HASH_WORDS = 8;
constexpr float EWC_LAMBDA = 400.0f;
constexpr float LR_DEFAULT = 0.001f;
constexpr float GRAD_CLIP = 5.0f;
constexpr int N_QUBITS = 300;
constexpr float COHERENCE = 0.99f;

namespace SiameseTwinAI_Windows {

struct SensorHash { uint64_t w[HASH_WORDS]; uint32_t sid; uint32_t ts; float coh; float ph; };
struct ClusterState { uint64_t centroid[HASH_WORDS]; int id; int n; float mh; int thr; float pri; };
struct EWCState { float* theta_star; float* fisher; float norm; float lam; int task; int np; };
struct MAIAJob { int type; int bs; int sq; int ep; int pri; char task[64]; char ckpt[128]; };


// Kernel 0: webview2_transport
__global__ void hamming_kernel(const uint64_t* __restrict__ a, const uint64_t* __restrict__ b,
    int* __restrict__ dist, int n, int hw) {
    int tid = blockIdx.x*blockDim.x+threadIdx.x;
    if(tid>=n) return;
    int d=0;
    for(int w=0;w<hw;++w) d+=__popcll(a[tid*hw+w]^b[tid*hw+w]);
    dist[tid]=d;
}

// Kernel 1: webview2_transport
__global__ void fisher_kernel(const float* __restrict__ g, float* __restrict__ f, int np, int ns) {
    int tid=blockIdx.x*blockDim.x+threadIdx.x;
    if(tid>=np) return;
    float acc=0.f;
    for(int s=0;s<ns;++s){ float v=g[s*np+tid]; acc+=v*v; }
    f[tid]=acc/(float)ns;
}

// Kernel 2: webview2_transport
__global__ void ewc_grad_kernel(const float* __restrict__ th, const float* __restrict__ ts,
    const float* __restrict__ f, float* __restrict__ eg, float lam, int np) {
    int tid=blockIdx.x*blockDim.x+threadIdx.x;
    if(tid>=np) return;
    eg[tid]=lam*f[tid]*(th[tid]-ts[tid]);
}

// Kernel 3: webview2_transport
__global__ void normalize_kernel(float* __restrict__ e, int bs, int dim) {
    int bid=blockIdx.x;
    if(bid>=bs) return;
    __shared__ float sn[32];
    float* emb=e+bid*dim;
    float ls=0.f;
    for(int i=threadIdx.x;i<dim;i+=blockDim.x) ls+=emb[i]*emb[i];
    for(int o=WARP_SIZE/2;o>0;o>>=1) ls+=__shfl_down_sync(0xffffffff,ls,o);
    if(threadIdx.x%WARP_SIZE==0) sn[threadIdx.x/WARP_SIZE]=ls;
    __syncthreads();
    float norm=0.f;
    if(threadIdx.x<blockDim.x/WARP_SIZE) norm=sn[threadIdx.x];
    for(int o=WARP_SIZE/2;o>0;o>>=1) norm+=__shfl_down_sync(0xffffffff,norm,o);
    norm=sqrtf(norm+1e-8f);
    for(int i=threadIdx.x;i<dim;i+=blockDim.x) emb[i]/=norm;
}

// Kernel 4: webview2_transport
__global__ void topk_kernel(const float* __restrict__ g, float* __restrict__ sv,
    int* __restrict__ si, float thr, int np, int* __restrict__ ns) {
    int tid=blockIdx.x*blockDim.x+threadIdx.x;
    if(tid>=np) return;
    if(fabsf(g[tid])>=thr){ int idx=atomicAdd(ns,1); sv[idx]=g[tid]; si[idx]=tid; }
}

// Kernel 5: webview2_transport
__global__ void priority_kernel(float* __restrict__ p, const float* __restrict__ td,
    const int* __restrict__ idx, float alpha, float minp, float maxp, int n) {
    int tid=blockIdx.x*blockDim.x+threadIdx.x;
    if(tid>=n) return;
    float np2=powf(fabsf(td[tid])+minp,alpha);
    p[idx[tid]]=fminf(maxp,np2);
}

// Kernel 6: webview2_transport
__global__ void centroid_kernel(uint64_t* __restrict__ c, const uint64_t* __restrict__ s,
    const int* __restrict__ asgn, int* __restrict__ cnt, int n, int hw) {
    int tid=blockIdx.x*blockDim.x+threadIdx.x;
    if(tid>=n) return;
    int cl=asgn[tid];
    atomicAdd(&cnt[cl],1);
    for(int w=0;w<hw;++w){
        uint64_t sw=s[tid*hw+w];
        for(int b=0;b<64;++b){ int bit=(sw>>b)&1; atomicAdd((int*)&c[cl*hw+w],bit); }
    }
}

// Kernel 7: webview2_transport
__global__ void attention_kernel(const float* __restrict__ Q, const float* __restrict__ K,
    const float* __restrict__ V, float* __restrict__ O, int sl, int dm, int nh) {
    int h=blockIdx.z, r=blockIdx.y*blockDim.y+threadIdx.y, c=blockIdx.x*blockDim.x+threadIdx.x;
    if(r>=sl||c>=sl||h>=nh) return;
    int dh=dm/nh;
    float sc=rsqrtf((float)dh), s=0.f;
    for(int k=0;k<dh;++k) s+=Q[h*sl*dh+r*dh+k]*K[h*sl*dh+c*dh+k];
    O[h*sl*sl+r*sl+c]=s*sc;
}

// Kernel 8: webview2_transport
__global__ void dp_noise_kernel(float* __restrict__ g, const float* __restrict__ n,
    float std, float clip, int np) {
    int tid=blockIdx.x*blockDim.x+threadIdx.x;
    if(tid>=np) return;
    float v=g[tid]; float av=fabsf(v);
    if(av>clip) v=v*clip/av;
    g[tid]=v+std*n[tid];
}

// Kernel 9: webview2_transport
__global__ void gemm_kernel(const float* __restrict__ A, const float* __restrict__ B,
    float* __restrict__ C, int M, int N, int K, int bs) {
    __shared__ float As[TILE][TILE], Bs[TILE][TILE];
    int bat=blockIdx.z, r=blockIdx.y*TILE+threadIdx.y, c=blockIdx.x*TILE+threadIdx.x;
    float sum=0.f;
    for(int t=0;t<(K+TILE-1)/TILE;++t){
        int ac=t*TILE+threadIdx.x, br=t*TILE+threadIdx.y;
        As[threadIdx.y][threadIdx.x]=(r<M&&ac<K)?A[bat*M*K+r*K+ac]:0.f;
        Bs[threadIdx.y][threadIdx.x]=(br<K&&c<N)?B[bat*K*N+br*N+c]:0.f;
        __syncthreads();
        for(int k=0;k<TILE;++k) sum+=As[threadIdx.y][k]*Bs[k][threadIdx.x];
        __syncthreads();
    }
    if(r<M&&c<N) C[bat*M*N+r*N+c]=sum;
}

// ============================================================
// Host class: webview2_transportComponent0
// ============================================================
class webview2_transportComponent0 {
public:
    struct Config {
        int device_id=0; int batch_size=32; int embedding_dim=512;
        int n_params=10000000; float lr=0.001f; float ewc_lam=400.f;
        float anchor_alpha=0.5f; float grad_clip=5.f; float dp_eps=0.1f;
        int seed=42; bool fp16=true; bool tensor_cores=true; int n_streams=4;
    };
    explicit webview2_transportComponent0(const Config& cfg=Config{}): cfg_(cfg), step_(0) {
        CUDA_CHECK(cudaSetDevice(cfg_.device_id));
        CUBLAS_CHECK(cublasCreate(&cblas_));
        CURAND_CHECK(curandCreateGenerator(&crand_, CURAND_RNG_PSEUDO_DEFAULT));
        CURAND_CHECK(curandSetPseudoRandomGeneratorSeed(crand_, cfg_.seed));
        CUDA_CHECK(cudaMalloc(&d_p_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_f_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_ts_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_g_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_e_, cfg_.batch_size*cfg_.embedding_dim*sizeof(float)));
        streams_.resize(cfg_.n_streams);
        for(auto& s:streams_) CUDA_CHECK(cudaStreamCreate(&s));
        CURAND_CHECK(curandGenerateNormal(crand_,d_p_,cfg_.n_params,0.f,0.02f));
        CUDA_CHECK(cudaMemset(d_f_,0,cfg_.n_params*sizeof(float)));
    }

    /// @brief Method 0 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 0.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method0(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 0: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+0*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m0_ms"]=ms; return ms;
    }

    /// @brief Method 1 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 1.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method1(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 1: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+1*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m1_ms"]=ms; return ms;
    }

    /// @brief Method 2 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 2.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method2(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 2: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+2*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m2_ms"]=ms; return ms;
    }

    /// @brief Method 3 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 3.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method3(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 3: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+3*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m3_ms"]=ms; return ms;
    }

    /// @brief Method 4 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 4.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method4(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 4: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+4*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m4_ms"]=ms; return ms;
    }

    /// @brief Method 5 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 5.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method5(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 5: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+5*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m5_ms"]=ms; return ms;
    }

    /// @brief Method 6 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 6.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method6(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 6: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+6*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m6_ms"]=ms; return ms;
    }

    /// @brief Method 7 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 7.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method7(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 7: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+7*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m7_ms"]=ms; return ms;
    }

    /// @brief Method 8 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 8.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method8(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 8: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+8*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m8_ms"]=ms; return ms;
    }

    /// @brief Method 9 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 9.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method9(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 9: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+9*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m9_ms"]=ms; return ms;
    }

    /// @brief Method 10 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 10.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method10(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 10: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+10*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m10_ms"]=ms; return ms;
    }

    /// @brief Method 11 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 11.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method11(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 11: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+11*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m11_ms"]=ms; return ms;
    }

    /// @brief Method 12 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 12.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method12(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 12: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+12*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m12_ms"]=ms; return ms;
    }

    /// @brief Method 13 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 13.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method13(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 13: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+13*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m13_ms"]=ms; return ms;
    }

    /// @brief Method 14 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 14.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method14(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 14: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+14*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m14_ms"]=ms; return ms;
    }

    /// @brief Method 15 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 15.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method15(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 15: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+15*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m15_ms"]=ms; return ms;
    }

    /// @brief Method 16 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 16.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method16(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 16: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+16*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m16_ms"]=ms; return ms;
    }

    /// @brief Method 17 of webview2_transportComponent0 — SiameseTwinAI_Windows pipeline stage 17.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method17(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 17: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+17*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m17_ms"]=ms; return ms;
    }

    void compute_fisher(int ns) {
        int t=256,b=(cfg_.n_params+t-1)/t;
        fisher_kernel<<<b,t>>>(d_g_,d_f_,cfg_.n_params,ns);
        CUDA_CHECK(cudaDeviceSynchronize());
    }
    void save_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        CUDA_CHECK(cudaMemcpy(h.data(),d_p_,cfg_.n_params*sizeof(float),cudaMemcpyDeviceToHost));
        std::ofstream f(p,std::ios::binary);
        f.write(reinterpret_cast<const char*>(h.data()),h.size()*sizeof(float));
    }
    void load_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        std::ifstream f(p,std::ios::binary);
        f.read(reinterpret_cast<char*>(h.data()),h.size()*sizeof(float));
        CUDA_CHECK(cudaMemcpy(d_p_,h.data(),cfg_.n_params*sizeof(float),cudaMemcpyHostToDevice));
    }
    const std::unordered_map<std::string,float>& metrics() const { return metrics_; }
    long step() const { return step_; }
    ~webview2_transportComponent0() {
        if(d_p_) cudaFree(d_p_); if(d_f_) cudaFree(d_f_);
        if(d_ts_) cudaFree(d_ts_); if(d_g_) cudaFree(d_g_);
        if(d_e_) cudaFree(d_e_);
        for(auto& s:streams_) cudaStreamDestroy(s);
        cublasDestroy(cblas_); curandDestroyGenerator(crand_);
    }
private:
    Config cfg_; long step_;
    cublasHandle_t cblas_; curandGenerator_t crand_;
    float *d_p_=nullptr,*d_f_=nullptr,*d_ts_=nullptr,*d_g_=nullptr,*d_e_=nullptr;
    std::vector<cudaStream_t> streams_;
    std::unordered_map<std::string,float> metrics_;
};

// ============================================================
// Host class: webview2_transportComponent1
// ============================================================
class webview2_transportComponent1 {
public:
    struct Config {
        int device_id=0; int batch_size=32; int embedding_dim=512;
        int n_params=10000000; float lr=0.001f; float ewc_lam=400.f;
        float anchor_alpha=0.5f; float grad_clip=5.f; float dp_eps=0.1f;
        int seed=42; bool fp16=true; bool tensor_cores=true; int n_streams=4;
    };
    explicit webview2_transportComponent1(const Config& cfg=Config{}): cfg_(cfg), step_(0) {
        CUDA_CHECK(cudaSetDevice(cfg_.device_id));
        CUBLAS_CHECK(cublasCreate(&cblas_));
        CURAND_CHECK(curandCreateGenerator(&crand_, CURAND_RNG_PSEUDO_DEFAULT));
        CURAND_CHECK(curandSetPseudoRandomGeneratorSeed(crand_, cfg_.seed));
        CUDA_CHECK(cudaMalloc(&d_p_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_f_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_ts_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_g_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_e_, cfg_.batch_size*cfg_.embedding_dim*sizeof(float)));
        streams_.resize(cfg_.n_streams);
        for(auto& s:streams_) CUDA_CHECK(cudaStreamCreate(&s));
        CURAND_CHECK(curandGenerateNormal(crand_,d_p_,cfg_.n_params,0.f,0.02f));
        CUDA_CHECK(cudaMemset(d_f_,0,cfg_.n_params*sizeof(float)));
    }

    /// @brief Method 0 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 0.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method0(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 0: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+0*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m0_ms"]=ms; return ms;
    }

    /// @brief Method 1 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 1.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method1(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 1: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+1*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m1_ms"]=ms; return ms;
    }

    /// @brief Method 2 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 2.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method2(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 2: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+2*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m2_ms"]=ms; return ms;
    }

    /// @brief Method 3 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 3.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method3(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 3: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+3*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m3_ms"]=ms; return ms;
    }

    /// @brief Method 4 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 4.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method4(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 4: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+4*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m4_ms"]=ms; return ms;
    }

    /// @brief Method 5 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 5.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method5(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 5: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+5*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m5_ms"]=ms; return ms;
    }

    /// @brief Method 6 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 6.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method6(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 6: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+6*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m6_ms"]=ms; return ms;
    }

    /// @brief Method 7 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 7.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method7(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 7: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+7*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m7_ms"]=ms; return ms;
    }

    /// @brief Method 8 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 8.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method8(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 8: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+8*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m8_ms"]=ms; return ms;
    }

    /// @brief Method 9 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 9.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method9(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 9: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+9*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m9_ms"]=ms; return ms;
    }

    /// @brief Method 10 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 10.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method10(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 10: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+10*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m10_ms"]=ms; return ms;
    }

    /// @brief Method 11 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 11.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method11(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 11: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+11*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m11_ms"]=ms; return ms;
    }

    /// @brief Method 12 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 12.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method12(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 12: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+12*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m12_ms"]=ms; return ms;
    }

    /// @brief Method 13 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 13.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method13(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 13: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+13*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m13_ms"]=ms; return ms;
    }

    /// @brief Method 14 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 14.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method14(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 14: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+14*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m14_ms"]=ms; return ms;
    }

    /// @brief Method 15 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 15.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method15(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 15: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+15*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m15_ms"]=ms; return ms;
    }

    /// @brief Method 16 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 16.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method16(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 16: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+16*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m16_ms"]=ms; return ms;
    }

    /// @brief Method 17 of webview2_transportComponent1 — SiameseTwinAI_Windows pipeline stage 17.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method17(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 17: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+17*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m17_ms"]=ms; return ms;
    }

    void compute_fisher(int ns) {
        int t=256,b=(cfg_.n_params+t-1)/t;
        fisher_kernel<<<b,t>>>(d_g_,d_f_,cfg_.n_params,ns);
        CUDA_CHECK(cudaDeviceSynchronize());
    }
    void save_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        CUDA_CHECK(cudaMemcpy(h.data(),d_p_,cfg_.n_params*sizeof(float),cudaMemcpyDeviceToHost));
        std::ofstream f(p,std::ios::binary);
        f.write(reinterpret_cast<const char*>(h.data()),h.size()*sizeof(float));
    }
    void load_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        std::ifstream f(p,std::ios::binary);
        f.read(reinterpret_cast<char*>(h.data()),h.size()*sizeof(float));
        CUDA_CHECK(cudaMemcpy(d_p_,h.data(),cfg_.n_params*sizeof(float),cudaMemcpyHostToDevice));
    }
    const std::unordered_map<std::string,float>& metrics() const { return metrics_; }
    long step() const { return step_; }
    ~webview2_transportComponent1() {
        if(d_p_) cudaFree(d_p_); if(d_f_) cudaFree(d_f_);
        if(d_ts_) cudaFree(d_ts_); if(d_g_) cudaFree(d_g_);
        if(d_e_) cudaFree(d_e_);
        for(auto& s:streams_) cudaStreamDestroy(s);
        cublasDestroy(cblas_); curandDestroyGenerator(crand_);
    }
private:
    Config cfg_; long step_;
    cublasHandle_t cblas_; curandGenerator_t crand_;
    float *d_p_=nullptr,*d_f_=nullptr,*d_ts_=nullptr,*d_g_=nullptr,*d_e_=nullptr;
    std::vector<cudaStream_t> streams_;
    std::unordered_map<std::string,float> metrics_;
};

// ============================================================
// Host class: webview2_transportComponent2
// ============================================================
class webview2_transportComponent2 {
public:
    struct Config {
        int device_id=0; int batch_size=32; int embedding_dim=512;
        int n_params=10000000; float lr=0.001f; float ewc_lam=400.f;
        float anchor_alpha=0.5f; float grad_clip=5.f; float dp_eps=0.1f;
        int seed=42; bool fp16=true; bool tensor_cores=true; int n_streams=4;
    };
    explicit webview2_transportComponent2(const Config& cfg=Config{}): cfg_(cfg), step_(0) {
        CUDA_CHECK(cudaSetDevice(cfg_.device_id));
        CUBLAS_CHECK(cublasCreate(&cblas_));
        CURAND_CHECK(curandCreateGenerator(&crand_, CURAND_RNG_PSEUDO_DEFAULT));
        CURAND_CHECK(curandSetPseudoRandomGeneratorSeed(crand_, cfg_.seed));
        CUDA_CHECK(cudaMalloc(&d_p_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_f_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_ts_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_g_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_e_, cfg_.batch_size*cfg_.embedding_dim*sizeof(float)));
        streams_.resize(cfg_.n_streams);
        for(auto& s:streams_) CUDA_CHECK(cudaStreamCreate(&s));
        CURAND_CHECK(curandGenerateNormal(crand_,d_p_,cfg_.n_params,0.f,0.02f));
        CUDA_CHECK(cudaMemset(d_f_,0,cfg_.n_params*sizeof(float)));
    }

    /// @brief Method 0 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 0.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method0(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 0: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+0*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m0_ms"]=ms; return ms;
    }

    /// @brief Method 1 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 1.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method1(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 1: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+1*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m1_ms"]=ms; return ms;
    }

    /// @brief Method 2 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 2.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method2(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 2: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+2*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m2_ms"]=ms; return ms;
    }

    /// @brief Method 3 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 3.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method3(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 3: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+3*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m3_ms"]=ms; return ms;
    }

    /// @brief Method 4 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 4.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method4(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 4: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+4*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m4_ms"]=ms; return ms;
    }

    /// @brief Method 5 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 5.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method5(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 5: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+5*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m5_ms"]=ms; return ms;
    }

    /// @brief Method 6 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 6.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method6(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 6: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+6*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m6_ms"]=ms; return ms;
    }

    /// @brief Method 7 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 7.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method7(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 7: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+7*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m7_ms"]=ms; return ms;
    }

    /// @brief Method 8 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 8.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method8(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 8: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+8*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m8_ms"]=ms; return ms;
    }

    /// @brief Method 9 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 9.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method9(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 9: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+9*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m9_ms"]=ms; return ms;
    }

    /// @brief Method 10 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 10.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method10(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 10: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+10*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m10_ms"]=ms; return ms;
    }

    /// @brief Method 11 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 11.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method11(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 11: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+11*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m11_ms"]=ms; return ms;
    }

    /// @brief Method 12 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 12.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method12(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 12: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+12*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m12_ms"]=ms; return ms;
    }

    /// @brief Method 13 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 13.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method13(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 13: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+13*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m13_ms"]=ms; return ms;
    }

    /// @brief Method 14 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 14.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method14(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 14: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+14*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m14_ms"]=ms; return ms;
    }

    /// @brief Method 15 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 15.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method15(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 15: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+15*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m15_ms"]=ms; return ms;
    }

    /// @brief Method 16 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 16.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method16(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 16: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+16*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m16_ms"]=ms; return ms;
    }

    /// @brief Method 17 of webview2_transportComponent2 — SiameseTwinAI_Windows pipeline stage 17.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method17(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 17: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+17*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m17_ms"]=ms; return ms;
    }

    void compute_fisher(int ns) {
        int t=256,b=(cfg_.n_params+t-1)/t;
        fisher_kernel<<<b,t>>>(d_g_,d_f_,cfg_.n_params,ns);
        CUDA_CHECK(cudaDeviceSynchronize());
    }
    void save_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        CUDA_CHECK(cudaMemcpy(h.data(),d_p_,cfg_.n_params*sizeof(float),cudaMemcpyDeviceToHost));
        std::ofstream f(p,std::ios::binary);
        f.write(reinterpret_cast<const char*>(h.data()),h.size()*sizeof(float));
    }
    void load_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        std::ifstream f(p,std::ios::binary);
        f.read(reinterpret_cast<char*>(h.data()),h.size()*sizeof(float));
        CUDA_CHECK(cudaMemcpy(d_p_,h.data(),cfg_.n_params*sizeof(float),cudaMemcpyHostToDevice));
    }
    const std::unordered_map<std::string,float>& metrics() const { return metrics_; }
    long step() const { return step_; }
    ~webview2_transportComponent2() {
        if(d_p_) cudaFree(d_p_); if(d_f_) cudaFree(d_f_);
        if(d_ts_) cudaFree(d_ts_); if(d_g_) cudaFree(d_g_);
        if(d_e_) cudaFree(d_e_);
        for(auto& s:streams_) cudaStreamDestroy(s);
        cublasDestroy(cblas_); curandDestroyGenerator(crand_);
    }
private:
    Config cfg_; long step_;
    cublasHandle_t cblas_; curandGenerator_t crand_;
    float *d_p_=nullptr,*d_f_=nullptr,*d_ts_=nullptr,*d_g_=nullptr,*d_e_=nullptr;
    std::vector<cudaStream_t> streams_;
    std::unordered_map<std::string,float> metrics_;
};

// ============================================================
// Host class: webview2_transportComponent3
// ============================================================
class webview2_transportComponent3 {
public:
    struct Config {
        int device_id=0; int batch_size=32; int embedding_dim=512;
        int n_params=10000000; float lr=0.001f; float ewc_lam=400.f;
        float anchor_alpha=0.5f; float grad_clip=5.f; float dp_eps=0.1f;
        int seed=42; bool fp16=true; bool tensor_cores=true; int n_streams=4;
    };
    explicit webview2_transportComponent3(const Config& cfg=Config{}): cfg_(cfg), step_(0) {
        CUDA_CHECK(cudaSetDevice(cfg_.device_id));
        CUBLAS_CHECK(cublasCreate(&cblas_));
        CURAND_CHECK(curandCreateGenerator(&crand_, CURAND_RNG_PSEUDO_DEFAULT));
        CURAND_CHECK(curandSetPseudoRandomGeneratorSeed(crand_, cfg_.seed));
        CUDA_CHECK(cudaMalloc(&d_p_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_f_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_ts_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_g_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_e_, cfg_.batch_size*cfg_.embedding_dim*sizeof(float)));
        streams_.resize(cfg_.n_streams);
        for(auto& s:streams_) CUDA_CHECK(cudaStreamCreate(&s));
        CURAND_CHECK(curandGenerateNormal(crand_,d_p_,cfg_.n_params,0.f,0.02f));
        CUDA_CHECK(cudaMemset(d_f_,0,cfg_.n_params*sizeof(float)));
    }

    /// @brief Method 0 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 0.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method0(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 0: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+0*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m0_ms"]=ms; return ms;
    }

    /// @brief Method 1 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 1.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method1(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 1: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+1*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m1_ms"]=ms; return ms;
    }

    /// @brief Method 2 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 2.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method2(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 2: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+2*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m2_ms"]=ms; return ms;
    }

    /// @brief Method 3 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 3.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method3(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 3: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+3*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m3_ms"]=ms; return ms;
    }

    /// @brief Method 4 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 4.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method4(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 4: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+4*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m4_ms"]=ms; return ms;
    }

    /// @brief Method 5 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 5.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method5(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 5: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+5*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m5_ms"]=ms; return ms;
    }

    /// @brief Method 6 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 6.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method6(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 6: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+6*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m6_ms"]=ms; return ms;
    }

    /// @brief Method 7 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 7.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method7(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 7: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+7*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m7_ms"]=ms; return ms;
    }

    /// @brief Method 8 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 8.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method8(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 8: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+8*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m8_ms"]=ms; return ms;
    }

    /// @brief Method 9 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 9.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method9(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 9: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+9*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m9_ms"]=ms; return ms;
    }

    /// @brief Method 10 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 10.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method10(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 10: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+10*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m10_ms"]=ms; return ms;
    }

    /// @brief Method 11 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 11.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method11(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 11: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+11*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m11_ms"]=ms; return ms;
    }

    /// @brief Method 12 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 12.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method12(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 12: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+12*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m12_ms"]=ms; return ms;
    }

    /// @brief Method 13 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 13.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method13(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 13: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+13*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m13_ms"]=ms; return ms;
    }

    /// @brief Method 14 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 14.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method14(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 14: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+14*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m14_ms"]=ms; return ms;
    }

    /// @brief Method 15 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 15.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method15(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 15: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+15*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m15_ms"]=ms; return ms;
    }

    /// @brief Method 16 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 16.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method16(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 16: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+16*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m16_ms"]=ms; return ms;
    }

    /// @brief Method 17 of webview2_transportComponent3 — SiameseTwinAI_Windows pipeline stage 17.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method17(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 17: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+17*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m17_ms"]=ms; return ms;
    }

    void compute_fisher(int ns) {
        int t=256,b=(cfg_.n_params+t-1)/t;
        fisher_kernel<<<b,t>>>(d_g_,d_f_,cfg_.n_params,ns);
        CUDA_CHECK(cudaDeviceSynchronize());
    }
    void save_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        CUDA_CHECK(cudaMemcpy(h.data(),d_p_,cfg_.n_params*sizeof(float),cudaMemcpyDeviceToHost));
        std::ofstream f(p,std::ios::binary);
        f.write(reinterpret_cast<const char*>(h.data()),h.size()*sizeof(float));
    }
    void load_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        std::ifstream f(p,std::ios::binary);
        f.read(reinterpret_cast<char*>(h.data()),h.size()*sizeof(float));
        CUDA_CHECK(cudaMemcpy(d_p_,h.data(),cfg_.n_params*sizeof(float),cudaMemcpyHostToDevice));
    }
    const std::unordered_map<std::string,float>& metrics() const { return metrics_; }
    long step() const { return step_; }
    ~webview2_transportComponent3() {
        if(d_p_) cudaFree(d_p_); if(d_f_) cudaFree(d_f_);
        if(d_ts_) cudaFree(d_ts_); if(d_g_) cudaFree(d_g_);
        if(d_e_) cudaFree(d_e_);
        for(auto& s:streams_) cudaStreamDestroy(s);
        cublasDestroy(cblas_); curandDestroyGenerator(crand_);
    }
private:
    Config cfg_; long step_;
    cublasHandle_t cblas_; curandGenerator_t crand_;
    float *d_p_=nullptr,*d_f_=nullptr,*d_ts_=nullptr,*d_g_=nullptr,*d_e_=nullptr;
    std::vector<cudaStream_t> streams_;
    std::unordered_map<std::string,float> metrics_;
};

// ============================================================
// Host class: webview2_transportComponent4
// ============================================================
class webview2_transportComponent4 {
public:
    struct Config {
        int device_id=0; int batch_size=32; int embedding_dim=512;
        int n_params=10000000; float lr=0.001f; float ewc_lam=400.f;
        float anchor_alpha=0.5f; float grad_clip=5.f; float dp_eps=0.1f;
        int seed=42; bool fp16=true; bool tensor_cores=true; int n_streams=4;
    };
    explicit webview2_transportComponent4(const Config& cfg=Config{}): cfg_(cfg), step_(0) {
        CUDA_CHECK(cudaSetDevice(cfg_.device_id));
        CUBLAS_CHECK(cublasCreate(&cblas_));
        CURAND_CHECK(curandCreateGenerator(&crand_, CURAND_RNG_PSEUDO_DEFAULT));
        CURAND_CHECK(curandSetPseudoRandomGeneratorSeed(crand_, cfg_.seed));
        CUDA_CHECK(cudaMalloc(&d_p_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_f_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_ts_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_g_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_e_, cfg_.batch_size*cfg_.embedding_dim*sizeof(float)));
        streams_.resize(cfg_.n_streams);
        for(auto& s:streams_) CUDA_CHECK(cudaStreamCreate(&s));
        CURAND_CHECK(curandGenerateNormal(crand_,d_p_,cfg_.n_params,0.f,0.02f));
        CUDA_CHECK(cudaMemset(d_f_,0,cfg_.n_params*sizeof(float)));
    }

    /// @brief Method 0 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 0.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method0(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 0: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+0*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m0_ms"]=ms; return ms;
    }

    /// @brief Method 1 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 1.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method1(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 1: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+1*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m1_ms"]=ms; return ms;
    }

    /// @brief Method 2 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 2.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method2(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 2: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+2*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m2_ms"]=ms; return ms;
    }

    /// @brief Method 3 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 3.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method3(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 3: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+3*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m3_ms"]=ms; return ms;
    }

    /// @brief Method 4 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 4.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method4(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 4: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+4*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m4_ms"]=ms; return ms;
    }

    /// @brief Method 5 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 5.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method5(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 5: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+5*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m5_ms"]=ms; return ms;
    }

    /// @brief Method 6 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 6.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method6(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 6: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+6*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m6_ms"]=ms; return ms;
    }

    /// @brief Method 7 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 7.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method7(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 7: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+7*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m7_ms"]=ms; return ms;
    }

    /// @brief Method 8 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 8.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method8(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 8: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+8*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m8_ms"]=ms; return ms;
    }

    /// @brief Method 9 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 9.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method9(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 9: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+9*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m9_ms"]=ms; return ms;
    }

    /// @brief Method 10 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 10.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method10(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 10: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+10*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m10_ms"]=ms; return ms;
    }

    /// @brief Method 11 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 11.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method11(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 11: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+11*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m11_ms"]=ms; return ms;
    }

    /// @brief Method 12 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 12.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method12(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 12: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+12*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m12_ms"]=ms; return ms;
    }

    /// @brief Method 13 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 13.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method13(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 13: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+13*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m13_ms"]=ms; return ms;
    }

    /// @brief Method 14 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 14.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method14(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 14: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+14*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m14_ms"]=ms; return ms;
    }

    /// @brief Method 15 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 15.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method15(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 15: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+15*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m15_ms"]=ms; return ms;
    }

    /// @brief Method 16 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 16.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method16(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 16: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+16*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m16_ms"]=ms; return ms;
    }

    /// @brief Method 17 of webview2_transportComponent4 — SiameseTwinAI_Windows pipeline stage 17.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method17(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 17: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+17*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m17_ms"]=ms; return ms;
    }

    void compute_fisher(int ns) {
        int t=256,b=(cfg_.n_params+t-1)/t;
        fisher_kernel<<<b,t>>>(d_g_,d_f_,cfg_.n_params,ns);
        CUDA_CHECK(cudaDeviceSynchronize());
    }
    void save_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        CUDA_CHECK(cudaMemcpy(h.data(),d_p_,cfg_.n_params*sizeof(float),cudaMemcpyDeviceToHost));
        std::ofstream f(p,std::ios::binary);
        f.write(reinterpret_cast<const char*>(h.data()),h.size()*sizeof(float));
    }
    void load_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        std::ifstream f(p,std::ios::binary);
        f.read(reinterpret_cast<char*>(h.data()),h.size()*sizeof(float));
        CUDA_CHECK(cudaMemcpy(d_p_,h.data(),cfg_.n_params*sizeof(float),cudaMemcpyHostToDevice));
    }
    const std::unordered_map<std::string,float>& metrics() const { return metrics_; }
    long step() const { return step_; }
    ~webview2_transportComponent4() {
        if(d_p_) cudaFree(d_p_); if(d_f_) cudaFree(d_f_);
        if(d_ts_) cudaFree(d_ts_); if(d_g_) cudaFree(d_g_);
        if(d_e_) cudaFree(d_e_);
        for(auto& s:streams_) cudaStreamDestroy(s);
        cublasDestroy(cblas_); curandDestroyGenerator(crand_);
    }
private:
    Config cfg_; long step_;
    cublasHandle_t cblas_; curandGenerator_t crand_;
    float *d_p_=nullptr,*d_f_=nullptr,*d_ts_=nullptr,*d_g_=nullptr,*d_e_=nullptr;
    std::vector<cudaStream_t> streams_;
    std::unordered_map<std::string,float> metrics_;
};

// ============================================================
// Host class: webview2_transportComponent5
// ============================================================
class webview2_transportComponent5 {
public:
    struct Config {
        int device_id=0; int batch_size=32; int embedding_dim=512;
        int n_params=10000000; float lr=0.001f; float ewc_lam=400.f;
        float anchor_alpha=0.5f; float grad_clip=5.f; float dp_eps=0.1f;
        int seed=42; bool fp16=true; bool tensor_cores=true; int n_streams=4;
    };
    explicit webview2_transportComponent5(const Config& cfg=Config{}): cfg_(cfg), step_(0) {
        CUDA_CHECK(cudaSetDevice(cfg_.device_id));
        CUBLAS_CHECK(cublasCreate(&cblas_));
        CURAND_CHECK(curandCreateGenerator(&crand_, CURAND_RNG_PSEUDO_DEFAULT));
        CURAND_CHECK(curandSetPseudoRandomGeneratorSeed(crand_, cfg_.seed));
        CUDA_CHECK(cudaMalloc(&d_p_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_f_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_ts_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_g_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_e_, cfg_.batch_size*cfg_.embedding_dim*sizeof(float)));
        streams_.resize(cfg_.n_streams);
        for(auto& s:streams_) CUDA_CHECK(cudaStreamCreate(&s));
        CURAND_CHECK(curandGenerateNormal(crand_,d_p_,cfg_.n_params,0.f,0.02f));
        CUDA_CHECK(cudaMemset(d_f_,0,cfg_.n_params*sizeof(float)));
    }

    /// @brief Method 0 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 0.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method0(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 0: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+0*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m0_ms"]=ms; return ms;
    }

    /// @brief Method 1 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 1.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method1(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 1: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+1*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m1_ms"]=ms; return ms;
    }

    /// @brief Method 2 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 2.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method2(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 2: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+2*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m2_ms"]=ms; return ms;
    }

    /// @brief Method 3 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 3.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method3(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 3: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+3*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m3_ms"]=ms; return ms;
    }

    /// @brief Method 4 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 4.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method4(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 4: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+4*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m4_ms"]=ms; return ms;
    }

    /// @brief Method 5 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 5.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method5(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 5: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+5*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m5_ms"]=ms; return ms;
    }

    /// @brief Method 6 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 6.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method6(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 6: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+6*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m6_ms"]=ms; return ms;
    }

    /// @brief Method 7 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 7.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method7(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 7: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+7*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m7_ms"]=ms; return ms;
    }

    /// @brief Method 8 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 8.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method8(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 8: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+8*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m8_ms"]=ms; return ms;
    }

    /// @brief Method 9 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 9.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method9(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 9: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+9*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m9_ms"]=ms; return ms;
    }

    /// @brief Method 10 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 10.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method10(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 10: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+10*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m10_ms"]=ms; return ms;
    }

    /// @brief Method 11 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 11.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method11(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 11: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+11*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m11_ms"]=ms; return ms;
    }

    /// @brief Method 12 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 12.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method12(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 12: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+12*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m12_ms"]=ms; return ms;
    }

    /// @brief Method 13 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 13.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method13(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 13: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+13*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m13_ms"]=ms; return ms;
    }

    /// @brief Method 14 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 14.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method14(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 14: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+14*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m14_ms"]=ms; return ms;
    }

    /// @brief Method 15 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 15.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method15(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 15: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+15*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m15_ms"]=ms; return ms;
    }

    /// @brief Method 16 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 16.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method16(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 16: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+16*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m16_ms"]=ms; return ms;
    }

    /// @brief Method 17 of webview2_transportComponent5 — SiameseTwinAI_Windows pipeline stage 17.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method17(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 17: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+17*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m17_ms"]=ms; return ms;
    }

    void compute_fisher(int ns) {
        int t=256,b=(cfg_.n_params+t-1)/t;
        fisher_kernel<<<b,t>>>(d_g_,d_f_,cfg_.n_params,ns);
        CUDA_CHECK(cudaDeviceSynchronize());
    }
    void save_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        CUDA_CHECK(cudaMemcpy(h.data(),d_p_,cfg_.n_params*sizeof(float),cudaMemcpyDeviceToHost));
        std::ofstream f(p,std::ios::binary);
        f.write(reinterpret_cast<const char*>(h.data()),h.size()*sizeof(float));
    }
    void load_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        std::ifstream f(p,std::ios::binary);
        f.read(reinterpret_cast<char*>(h.data()),h.size()*sizeof(float));
        CUDA_CHECK(cudaMemcpy(d_p_,h.data(),cfg_.n_params*sizeof(float),cudaMemcpyHostToDevice));
    }
    const std::unordered_map<std::string,float>& metrics() const { return metrics_; }
    long step() const { return step_; }
    ~webview2_transportComponent5() {
        if(d_p_) cudaFree(d_p_); if(d_f_) cudaFree(d_f_);
        if(d_ts_) cudaFree(d_ts_); if(d_g_) cudaFree(d_g_);
        if(d_e_) cudaFree(d_e_);
        for(auto& s:streams_) cudaStreamDestroy(s);
        cublasDestroy(cblas_); curandDestroyGenerator(crand_);
    }
private:
    Config cfg_; long step_;
    cublasHandle_t cblas_; curandGenerator_t crand_;
    float *d_p_=nullptr,*d_f_=nullptr,*d_ts_=nullptr,*d_g_=nullptr,*d_e_=nullptr;
    std::vector<cudaStream_t> streams_;
    std::unordered_map<std::string,float> metrics_;
};

// ============================================================
// Host class: webview2_transportComponent6
// ============================================================
class webview2_transportComponent6 {
public:
    struct Config {
        int device_id=0; int batch_size=32; int embedding_dim=512;
        int n_params=10000000; float lr=0.001f; float ewc_lam=400.f;
        float anchor_alpha=0.5f; float grad_clip=5.f; float dp_eps=0.1f;
        int seed=42; bool fp16=true; bool tensor_cores=true; int n_streams=4;
    };
    explicit webview2_transportComponent6(const Config& cfg=Config{}): cfg_(cfg), step_(0) {
        CUDA_CHECK(cudaSetDevice(cfg_.device_id));
        CUBLAS_CHECK(cublasCreate(&cblas_));
        CURAND_CHECK(curandCreateGenerator(&crand_, CURAND_RNG_PSEUDO_DEFAULT));
        CURAND_CHECK(curandSetPseudoRandomGeneratorSeed(crand_, cfg_.seed));
        CUDA_CHECK(cudaMalloc(&d_p_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_f_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_ts_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_g_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_e_, cfg_.batch_size*cfg_.embedding_dim*sizeof(float)));
        streams_.resize(cfg_.n_streams);
        for(auto& s:streams_) CUDA_CHECK(cudaStreamCreate(&s));
        CURAND_CHECK(curandGenerateNormal(crand_,d_p_,cfg_.n_params,0.f,0.02f));
        CUDA_CHECK(cudaMemset(d_f_,0,cfg_.n_params*sizeof(float)));
    }

    /// @brief Method 0 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 0.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method0(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 0: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+0*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m0_ms"]=ms; return ms;
    }

    /// @brief Method 1 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 1.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method1(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 1: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+1*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m1_ms"]=ms; return ms;
    }

    /// @brief Method 2 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 2.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method2(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 2: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+2*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m2_ms"]=ms; return ms;
    }

    /// @brief Method 3 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 3.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method3(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 3: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+3*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m3_ms"]=ms; return ms;
    }

    /// @brief Method 4 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 4.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method4(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 4: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+4*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m4_ms"]=ms; return ms;
    }

    /// @brief Method 5 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 5.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method5(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 5: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+5*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m5_ms"]=ms; return ms;
    }

    /// @brief Method 6 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 6.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method6(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 6: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+6*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m6_ms"]=ms; return ms;
    }

    /// @brief Method 7 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 7.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method7(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 7: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+7*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m7_ms"]=ms; return ms;
    }

    /// @brief Method 8 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 8.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method8(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 8: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+8*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m8_ms"]=ms; return ms;
    }

    /// @brief Method 9 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 9.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method9(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 9: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+9*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m9_ms"]=ms; return ms;
    }

    /// @brief Method 10 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 10.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method10(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 10: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+10*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m10_ms"]=ms; return ms;
    }

    /// @brief Method 11 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 11.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method11(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 11: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+11*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m11_ms"]=ms; return ms;
    }

    /// @brief Method 12 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 12.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method12(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 12: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+12*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m12_ms"]=ms; return ms;
    }

    /// @brief Method 13 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 13.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method13(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 13: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+13*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m13_ms"]=ms; return ms;
    }

    /// @brief Method 14 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 14.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method14(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 14: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+14*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m14_ms"]=ms; return ms;
    }

    /// @brief Method 15 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 15.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method15(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 15: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+15*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m15_ms"]=ms; return ms;
    }

    /// @brief Method 16 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 16.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method16(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 16: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+16*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m16_ms"]=ms; return ms;
    }

    /// @brief Method 17 of webview2_transportComponent6 — SiameseTwinAI_Windows pipeline stage 17.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method17(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 17: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+17*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m17_ms"]=ms; return ms;
    }

    void compute_fisher(int ns) {
        int t=256,b=(cfg_.n_params+t-1)/t;
        fisher_kernel<<<b,t>>>(d_g_,d_f_,cfg_.n_params,ns);
        CUDA_CHECK(cudaDeviceSynchronize());
    }
    void save_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        CUDA_CHECK(cudaMemcpy(h.data(),d_p_,cfg_.n_params*sizeof(float),cudaMemcpyDeviceToHost));
        std::ofstream f(p,std::ios::binary);
        f.write(reinterpret_cast<const char*>(h.data()),h.size()*sizeof(float));
    }
    void load_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        std::ifstream f(p,std::ios::binary);
        f.read(reinterpret_cast<char*>(h.data()),h.size()*sizeof(float));
        CUDA_CHECK(cudaMemcpy(d_p_,h.data(),cfg_.n_params*sizeof(float),cudaMemcpyHostToDevice));
    }
    const std::unordered_map<std::string,float>& metrics() const { return metrics_; }
    long step() const { return step_; }
    ~webview2_transportComponent6() {
        if(d_p_) cudaFree(d_p_); if(d_f_) cudaFree(d_f_);
        if(d_ts_) cudaFree(d_ts_); if(d_g_) cudaFree(d_g_);
        if(d_e_) cudaFree(d_e_);
        for(auto& s:streams_) cudaStreamDestroy(s);
        cublasDestroy(cblas_); curandDestroyGenerator(crand_);
    }
private:
    Config cfg_; long step_;
    cublasHandle_t cblas_; curandGenerator_t crand_;
    float *d_p_=nullptr,*d_f_=nullptr,*d_ts_=nullptr,*d_g_=nullptr,*d_e_=nullptr;
    std::vector<cudaStream_t> streams_;
    std::unordered_map<std::string,float> metrics_;
};

// ============================================================
// Host class: webview2_transportComponent7
// ============================================================
class webview2_transportComponent7 {
public:
    struct Config {
        int device_id=0; int batch_size=32; int embedding_dim=512;
        int n_params=10000000; float lr=0.001f; float ewc_lam=400.f;
        float anchor_alpha=0.5f; float grad_clip=5.f; float dp_eps=0.1f;
        int seed=42; bool fp16=true; bool tensor_cores=true; int n_streams=4;
    };
    explicit webview2_transportComponent7(const Config& cfg=Config{}): cfg_(cfg), step_(0) {
        CUDA_CHECK(cudaSetDevice(cfg_.device_id));
        CUBLAS_CHECK(cublasCreate(&cblas_));
        CURAND_CHECK(curandCreateGenerator(&crand_, CURAND_RNG_PSEUDO_DEFAULT));
        CURAND_CHECK(curandSetPseudoRandomGeneratorSeed(crand_, cfg_.seed));
        CUDA_CHECK(cudaMalloc(&d_p_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_f_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_ts_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_g_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_e_, cfg_.batch_size*cfg_.embedding_dim*sizeof(float)));
        streams_.resize(cfg_.n_streams);
        for(auto& s:streams_) CUDA_CHECK(cudaStreamCreate(&s));
        CURAND_CHECK(curandGenerateNormal(crand_,d_p_,cfg_.n_params,0.f,0.02f));
        CUDA_CHECK(cudaMemset(d_f_,0,cfg_.n_params*sizeof(float)));
    }

    /// @brief Method 0 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 0.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method0(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 0: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+0*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m0_ms"]=ms; return ms;
    }

    /// @brief Method 1 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 1.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method1(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 1: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+1*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m1_ms"]=ms; return ms;
    }

    /// @brief Method 2 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 2.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method2(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 2: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+2*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m2_ms"]=ms; return ms;
    }

    /// @brief Method 3 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 3.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method3(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 3: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+3*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m3_ms"]=ms; return ms;
    }

    /// @brief Method 4 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 4.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method4(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 4: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+4*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m4_ms"]=ms; return ms;
    }

    /// @brief Method 5 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 5.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method5(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 5: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+5*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m5_ms"]=ms; return ms;
    }

    /// @brief Method 6 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 6.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method6(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 6: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+6*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m6_ms"]=ms; return ms;
    }

    /// @brief Method 7 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 7.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method7(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 7: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+7*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m7_ms"]=ms; return ms;
    }

    /// @brief Method 8 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 8.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method8(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 8: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+8*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m8_ms"]=ms; return ms;
    }

    /// @brief Method 9 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 9.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method9(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 9: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+9*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m9_ms"]=ms; return ms;
    }

    /// @brief Method 10 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 10.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method10(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 10: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+10*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m10_ms"]=ms; return ms;
    }

    /// @brief Method 11 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 11.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method11(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 11: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+11*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m11_ms"]=ms; return ms;
    }

    /// @brief Method 12 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 12.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method12(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 12: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+12*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m12_ms"]=ms; return ms;
    }

    /// @brief Method 13 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 13.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method13(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 13: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+13*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m13_ms"]=ms; return ms;
    }

    /// @brief Method 14 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 14.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method14(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 14: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+14*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m14_ms"]=ms; return ms;
    }

    /// @brief Method 15 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 15.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method15(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 15: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+15*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m15_ms"]=ms; return ms;
    }

    /// @brief Method 16 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 16.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method16(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 16: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+16*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m16_ms"]=ms; return ms;
    }

    /// @brief Method 17 of webview2_transportComponent7 — SiameseTwinAI_Windows pipeline stage 17.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method17(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 17: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+17*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m17_ms"]=ms; return ms;
    }

    void compute_fisher(int ns) {
        int t=256,b=(cfg_.n_params+t-1)/t;
        fisher_kernel<<<b,t>>>(d_g_,d_f_,cfg_.n_params,ns);
        CUDA_CHECK(cudaDeviceSynchronize());
    }
    void save_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        CUDA_CHECK(cudaMemcpy(h.data(),d_p_,cfg_.n_params*sizeof(float),cudaMemcpyDeviceToHost));
        std::ofstream f(p,std::ios::binary);
        f.write(reinterpret_cast<const char*>(h.data()),h.size()*sizeof(float));
    }
    void load_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        std::ifstream f(p,std::ios::binary);
        f.read(reinterpret_cast<char*>(h.data()),h.size()*sizeof(float));
        CUDA_CHECK(cudaMemcpy(d_p_,h.data(),cfg_.n_params*sizeof(float),cudaMemcpyHostToDevice));
    }
    const std::unordered_map<std::string,float>& metrics() const { return metrics_; }
    long step() const { return step_; }
    ~webview2_transportComponent7() {
        if(d_p_) cudaFree(d_p_); if(d_f_) cudaFree(d_f_);
        if(d_ts_) cudaFree(d_ts_); if(d_g_) cudaFree(d_g_);
        if(d_e_) cudaFree(d_e_);
        for(auto& s:streams_) cudaStreamDestroy(s);
        cublasDestroy(cblas_); curandDestroyGenerator(crand_);
    }
private:
    Config cfg_; long step_;
    cublasHandle_t cblas_; curandGenerator_t crand_;
    float *d_p_=nullptr,*d_f_=nullptr,*d_ts_=nullptr,*d_g_=nullptr,*d_e_=nullptr;
    std::vector<cudaStream_t> streams_;
    std::unordered_map<std::string,float> metrics_;
};

// ============================================================
// Host class: webview2_transportComponent8
// ============================================================
class webview2_transportComponent8 {
public:
    struct Config {
        int device_id=0; int batch_size=32; int embedding_dim=512;
        int n_params=10000000; float lr=0.001f; float ewc_lam=400.f;
        float anchor_alpha=0.5f; float grad_clip=5.f; float dp_eps=0.1f;
        int seed=42; bool fp16=true; bool tensor_cores=true; int n_streams=4;
    };
    explicit webview2_transportComponent8(const Config& cfg=Config{}): cfg_(cfg), step_(0) {
        CUDA_CHECK(cudaSetDevice(cfg_.device_id));
        CUBLAS_CHECK(cublasCreate(&cblas_));
        CURAND_CHECK(curandCreateGenerator(&crand_, CURAND_RNG_PSEUDO_DEFAULT));
        CURAND_CHECK(curandSetPseudoRandomGeneratorSeed(crand_, cfg_.seed));
        CUDA_CHECK(cudaMalloc(&d_p_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_f_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_ts_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_g_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_e_, cfg_.batch_size*cfg_.embedding_dim*sizeof(float)));
        streams_.resize(cfg_.n_streams);
        for(auto& s:streams_) CUDA_CHECK(cudaStreamCreate(&s));
        CURAND_CHECK(curandGenerateNormal(crand_,d_p_,cfg_.n_params,0.f,0.02f));
        CUDA_CHECK(cudaMemset(d_f_,0,cfg_.n_params*sizeof(float)));
    }

    /// @brief Method 0 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 0.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method0(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 0: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+0*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m0_ms"]=ms; return ms;
    }

    /// @brief Method 1 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 1.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method1(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 1: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+1*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m1_ms"]=ms; return ms;
    }

    /// @brief Method 2 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 2.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method2(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 2: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+2*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m2_ms"]=ms; return ms;
    }

    /// @brief Method 3 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 3.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method3(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 3: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+3*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m3_ms"]=ms; return ms;
    }

    /// @brief Method 4 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 4.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method4(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 4: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+4*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m4_ms"]=ms; return ms;
    }

    /// @brief Method 5 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 5.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method5(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 5: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+5*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m5_ms"]=ms; return ms;
    }

    /// @brief Method 6 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 6.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method6(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 6: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+6*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m6_ms"]=ms; return ms;
    }

    /// @brief Method 7 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 7.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method7(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 7: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+7*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m7_ms"]=ms; return ms;
    }

    /// @brief Method 8 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 8.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method8(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 8: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+8*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m8_ms"]=ms; return ms;
    }

    /// @brief Method 9 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 9.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method9(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 9: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+9*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m9_ms"]=ms; return ms;
    }

    /// @brief Method 10 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 10.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method10(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 10: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+10*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m10_ms"]=ms; return ms;
    }

    /// @brief Method 11 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 11.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method11(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 11: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+11*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m11_ms"]=ms; return ms;
    }

    /// @brief Method 12 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 12.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method12(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 12: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+12*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m12_ms"]=ms; return ms;
    }

    /// @brief Method 13 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 13.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method13(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 13: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+13*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m13_ms"]=ms; return ms;
    }

    /// @brief Method 14 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 14.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method14(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 14: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+14*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m14_ms"]=ms; return ms;
    }

    /// @brief Method 15 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 15.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method15(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 15: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+15*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m15_ms"]=ms; return ms;
    }

    /// @brief Method 16 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 16.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method16(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 16: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+16*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m16_ms"]=ms; return ms;
    }

    /// @brief Method 17 of webview2_transportComponent8 — SiameseTwinAI_Windows pipeline stage 17.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method17(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 17: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+17*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m17_ms"]=ms; return ms;
    }

    void compute_fisher(int ns) {
        int t=256,b=(cfg_.n_params+t-1)/t;
        fisher_kernel<<<b,t>>>(d_g_,d_f_,cfg_.n_params,ns);
        CUDA_CHECK(cudaDeviceSynchronize());
    }
    void save_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        CUDA_CHECK(cudaMemcpy(h.data(),d_p_,cfg_.n_params*sizeof(float),cudaMemcpyDeviceToHost));
        std::ofstream f(p,std::ios::binary);
        f.write(reinterpret_cast<const char*>(h.data()),h.size()*sizeof(float));
    }
    void load_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        std::ifstream f(p,std::ios::binary);
        f.read(reinterpret_cast<char*>(h.data()),h.size()*sizeof(float));
        CUDA_CHECK(cudaMemcpy(d_p_,h.data(),cfg_.n_params*sizeof(float),cudaMemcpyHostToDevice));
    }
    const std::unordered_map<std::string,float>& metrics() const { return metrics_; }
    long step() const { return step_; }
    ~webview2_transportComponent8() {
        if(d_p_) cudaFree(d_p_); if(d_f_) cudaFree(d_f_);
        if(d_ts_) cudaFree(d_ts_); if(d_g_) cudaFree(d_g_);
        if(d_e_) cudaFree(d_e_);
        for(auto& s:streams_) cudaStreamDestroy(s);
        cublasDestroy(cblas_); curandDestroyGenerator(crand_);
    }
private:
    Config cfg_; long step_;
    cublasHandle_t cblas_; curandGenerator_t crand_;
    float *d_p_=nullptr,*d_f_=nullptr,*d_ts_=nullptr,*d_g_=nullptr,*d_e_=nullptr;
    std::vector<cudaStream_t> streams_;
    std::unordered_map<std::string,float> metrics_;
};

// ============================================================
// Host class: webview2_transportComponent9
// ============================================================
class webview2_transportComponent9 {
public:
    struct Config {
        int device_id=0; int batch_size=32; int embedding_dim=512;
        int n_params=10000000; float lr=0.001f; float ewc_lam=400.f;
        float anchor_alpha=0.5f; float grad_clip=5.f; float dp_eps=0.1f;
        int seed=42; bool fp16=true; bool tensor_cores=true; int n_streams=4;
    };
    explicit webview2_transportComponent9(const Config& cfg=Config{}): cfg_(cfg), step_(0) {
        CUDA_CHECK(cudaSetDevice(cfg_.device_id));
        CUBLAS_CHECK(cublasCreate(&cblas_));
        CURAND_CHECK(curandCreateGenerator(&crand_, CURAND_RNG_PSEUDO_DEFAULT));
        CURAND_CHECK(curandSetPseudoRandomGeneratorSeed(crand_, cfg_.seed));
        CUDA_CHECK(cudaMalloc(&d_p_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_f_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_ts_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_g_, cfg_.n_params*sizeof(float)));
        CUDA_CHECK(cudaMalloc(&d_e_, cfg_.batch_size*cfg_.embedding_dim*sizeof(float)));
        streams_.resize(cfg_.n_streams);
        for(auto& s:streams_) CUDA_CHECK(cudaStreamCreate(&s));
        CURAND_CHECK(curandGenerateNormal(crand_,d_p_,cfg_.n_params,0.f,0.02f));
        CUDA_CHECK(cudaMemset(d_f_,0,cfg_.n_params*sizeof(float)));
    }

    /// @brief Method 0 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 0.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method0(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 0: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+0*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m0_ms"]=ms; return ms;
    }

    /// @brief Method 1 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 1.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method1(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 1: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+1*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m1_ms"]=ms; return ms;
    }

    /// @brief Method 2 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 2.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method2(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 2: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+2*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m2_ms"]=ms; return ms;
    }

    /// @brief Method 3 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 3.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method3(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 3: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+3*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m3_ms"]=ms; return ms;
    }

    /// @brief Method 4 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 4.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method4(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 4: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+4*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m4_ms"]=ms; return ms;
    }

    /// @brief Method 5 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 5.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method5(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 5: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+5*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m5_ms"]=ms; return ms;
    }

    /// @brief Method 6 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 6.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method6(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 6: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+6*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m6_ms"]=ms; return ms;
    }

    /// @brief Method 7 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 7.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method7(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 7: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+7*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m7_ms"]=ms; return ms;
    }

    /// @brief Method 8 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 8.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method8(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 8: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+8*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m8_ms"]=ms; return ms;
    }

    /// @brief Method 9 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 9.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method9(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 9: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+9*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m9_ms"]=ms; return ms;
    }

    /// @brief Method 10 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 10.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method10(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 10: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+10*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m10_ms"]=ms; return ms;
    }

    /// @brief Method 11 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 11.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method11(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 11: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+11*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m11_ms"]=ms; return ms;
    }

    /// @brief Method 12 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 12.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method12(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 12: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+12*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m12_ms"]=ms; return ms;
    }

    /// @brief Method 13 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 13.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method13(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 13: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+13*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m13_ms"]=ms; return ms;
    }

    /// @brief Method 14 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 14.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method14(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 14: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+14*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m14_ms"]=ms; return ms;
    }

    /// @brief Method 15 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 15.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method15(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 15: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+15*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m15_ms"]=ms; return ms;
    }

    /// @brief Method 16 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 16.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method16(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 16: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+16*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m16_ms"]=ms; return ms;
    }

    /// @brief Method 17 of webview2_transportComponent9 — SiameseTwinAI_Windows pipeline stage 17.
    /// Applies CUDA-accelerated processing with EWC regularization.
    /// @param in_d Device input pointer. @param out_d Device output pointer.
    /// @param n Element count. @param stream CUDA stream.
    /// @return Kernel execution time in milliseconds.
    float method17(const float* in_d, float* out_d, int n, cudaStream_t stream=nullptr) {
        cudaEvent_t t0,t1;
        CUDA_CHECK(cudaEventCreate(&t0)); CUDA_CHECK(cudaEventCreate(&t1));
        CUDA_CHECK(cudaEventRecord(t0,stream));
        int thr=std::min(n,MAX_THREADS), blk=(n+thr-1)/thr;
        // Stage 17: parameterized kernel launch
        dp_noise_kernel<<<blk,thr,0,stream>>>(out_d,in_d,
            cfg_.lr*(1.f+17*0.01f), cfg_.grad_clip, n);
        // EWC regularization gradient
        if(cfg_.ewc_lam>0.f) {
            int pb=(cfg_.n_params+thr-1)/thr;
            ewc_grad_kernel<<<pb,thr,0,stream>>>(d_p_,d_ts_,d_f_,d_g_,cfg_.ewc_lam,cfg_.n_params);
        }
        // Normalize embeddings if applicable
        if(n>=cfg_.embedding_dim) {
            int ne=n/cfg_.embedding_dim;
            normalize_kernel<<<ne,256,0,stream>>>(out_d,ne,cfg_.embedding_dim);
        }
        CUDA_CHECK(cudaEventRecord(t1,stream));
        CUDA_CHECK(cudaEventSynchronize(t1));
        float ms=0.f; CUDA_CHECK(cudaEventElapsedTime(&ms,t0,t1));
        CUDA_CHECK(cudaEventDestroy(t0)); CUDA_CHECK(cudaEventDestroy(t1));
        ++step_; metrics_["m17_ms"]=ms; return ms;
    }

    void compute_fisher(int ns) {
        int t=256,b=(cfg_.n_params+t-1)/t;
        fisher_kernel<<<b,t>>>(d_g_,d_f_,cfg_.n_params,ns);
        CUDA_CHECK(cudaDeviceSynchronize());
    }
    void save_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        CUDA_CHECK(cudaMemcpy(h.data(),d_p_,cfg_.n_params*sizeof(float),cudaMemcpyDeviceToHost));
        std::ofstream f(p,std::ios::binary);
        f.write(reinterpret_cast<const char*>(h.data()),h.size()*sizeof(float));
    }
    void load_ckpt(const std::string& p) {
        std::vector<float> h(cfg_.n_params);
        std::ifstream f(p,std::ios::binary);
        f.read(reinterpret_cast<char*>(h.data()),h.size()*sizeof(float));
        CUDA_CHECK(cudaMemcpy(d_p_,h.data(),cfg_.n_params*sizeof(float),cudaMemcpyHostToDevice));
    }
    const std::unordered_map<std::string,float>& metrics() const { return metrics_; }
    long step() const { return step_; }
    ~webview2_transportComponent9() {
        if(d_p_) cudaFree(d_p_); if(d_f_) cudaFree(d_f_);
        if(d_ts_) cudaFree(d_ts_); if(d_g_) cudaFree(d_g_);
        if(d_e_) cudaFree(d_e_);
        for(auto& s:streams_) cudaStreamDestroy(s);
        cublasDestroy(cblas_); curandDestroyGenerator(crand_);
    }
private:
    Config cfg_; long step_;
    cublasHandle_t cblas_; curandGenerator_t crand_;
    float *d_p_=nullptr,*d_f_=nullptr,*d_ts_=nullptr,*d_g_=nullptr,*d_e_=nullptr;
    std::vector<cudaStream_t> streams_;
    std::unordered_map<std::string,float> metrics_;
};

} // namespace SiameseTwinAI_Windows

int main(int argc,char** argv) {
    int dc=0; CUDA_CHECK(cudaGetDeviceCount(&dc));
    printf("webview2_transport: %d CUDA device(s)\n",dc);
    if(!dc){ fprintf(stderr,"No CUDA\n"); return 1; }
    cudaDeviceProp p; CUDA_CHECK(cudaGetDeviceProperties(&p,0));
    printf("  Device: %s SM%d.%d %zuMB\n",p.name,p.major,p.minor,p.totalGlobalMem>>20);
    SiameseTwinAI_Windows::webview2_transportComponent0::Config cfg;
    cfg.n_params=1000000;
    SiameseTwinAI_Windows::webview2_transportComponent0 comp(cfg);
    float *di,*dout; int n=cfg.batch_size*512;
    CUDA_CHECK(cudaMalloc(&di,n*sizeof(float)));
    CUDA_CHECK(cudaMalloc(&dout,n*sizeof(float)));
    float tot=0.f;
    for(int i=0;i<100;++i) tot+=comp.method0(di,dout,n);
    printf("webview2_transport: %.3fms/iter %.0f samp/s\n",tot/100.f,(float)cfg.batch_size*100.f/(tot/1000.f));
    cudaFree(di); cudaFree(dout); return 0;
}