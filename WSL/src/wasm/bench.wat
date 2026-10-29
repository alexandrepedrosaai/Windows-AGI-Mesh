;; =============================================================================
;; Windows AGI Benchmark Lab — WebAssembly Text Format Benchmark
;; Copyright (c) 2026 Microsoft Corporation. All Rights Reserved.
;; =============================================================================
;; WebAssembly Text Format (WAT) — portable, sandboxed execution
;; Targets: Browser, Node.js, Wasmtime, Wasmer, WAMR, WasmEdge
;;
;; Build:
;;   wat2wasm bench.wat -o bench.wasm
;;   wasmtime bench.wasm
;;   node -e "const fs=require('fs'); WebAssembly.instantiate(fs.readFileSync('bench.wasm')).then(m=>m.instance.exports.run_all())"
;; =============================================================================

(module
  ;; Module metadata
  (;; Microsoft Windows AGI Benchmark Lab — WebAssembly Module ;;)

  ;; =========================================================================
  ;; Memory — 16 pages = 1 MB
  ;; =========================================================================
  (memory (export "memory") 16)

  ;; =========================================================================
  ;; Global variables
  ;; =========================================================================
  (global $iteration_count (mut i64) (i64.const 0))
  (global $result_f64      (mut f64)  (f64.const 0.0))
  (global $result_i64      (mut i64) (i64.const 0))
  (global $bench_start_ms  (mut f64)  (f64.const 0.0))

  ;; Memory layout:
  ;;   0x0000 - 0x3FFF : Array A (float64, 1024 elements = 8KB)
  ;;   0x4000 - 0x7FFF : Array B (float64, 1024 elements = 8KB)
  ;;   0x8000 - 0xBFFF : Array C (float64, 1024 elements = 8KB)
  ;;   0xC000 - 0xFFFF : Integer array (i64, 1024 elements = 8KB)
  (global $arr_a_base i32 (i32.const 0x0000))
  (global $arr_b_base i32 (i32.const 0x4000))
  (global $arr_c_base i32 (i32.const 0x8000))
  (global $arr_i_base i32 (i32.const 0xC000))

  ;; =========================================================================
  ;; Imports (from host environment)
  ;; =========================================================================
  (import "env" "performance_now" (func $perf_now (result f64)))
  (import "env" "console_log_f64" (func $log_f64 (param f64)))
  (import "env" "console_log_i64" (func $log_i64 (param i64)))

  ;; =========================================================================
  ;; Utility Functions
  ;; =========================================================================

  ;; Absolute value of f64
  (func $abs_f64 (param $x f64) (result f64)
    (f64.abs (local.get $x))
  )

  ;; Min of two i32
  (func $min_i32 (param $a i32) (param $b i32) (result i32)
    (select
      (local.get $a)
      (local.get $b)
      (i32.lt_s (local.get $a) (local.get $b))
    )
  )

  ;; Max of two i32
  (func $max_i32 (param $a i32) (param $b i32) (result i32)
    (select
      (local.get $a)
      (local.get $b)
      (i32.gt_s (local.get $a) (local.get $b))
    )
  )

  ;; =========================================================================
  ;; Array Initialization
  ;; =========================================================================

  (func $init_arrays (export "init_arrays")
    (local $i i32)
    (local $base_a i32)
    (local $base_b i32)
    (local $val_a f64)
    (local $val_b f64)

    (local.set $i (i32.const 0))
    (local.set $base_a (global.get $arr_a_base))
    (local.set $base_b (global.get $arr_b_base))

    (block $break
      (loop $loop
        (br_if $break (i32.ge_u (local.get $i) (i32.const 1024)))

        ;; A[i] = i * 0.001 + 1.0
        (local.set $val_a
          (f64.add
            (f64.mul (f64.convert_i32_u (local.get $i)) (f64.const 0.001))
            (f64.const 1.0)
          )
        )

        ;; B[i] = i * 0.002 + 2.0
        (local.set $val_b
          (f64.add
            (f64.mul (f64.convert_i32_u (local.get $i)) (f64.const 0.002))
            (f64.const 2.0)
          )
        )

        ;; Store A[i]
        (f64.store
          (i32.add (local.get $base_a) (i32.mul (local.get $i) (i32.const 8)))
          (local.get $val_a)
        )

        ;; Store B[i]
        (f64.store
          (i32.add (local.get $base_b) (i32.mul (local.get $i) (i32.const 8)))
          (local.get $val_b)
        )

        ;; C[i] = 0.0
        (f64.store
          (i32.add (global.get $arr_c_base) (i32.mul (local.get $i) (i32.const 8)))
          (f64.const 0.0)
        )

        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
  )

  ;; =========================================================================
  ;; Benchmark: Integer Arithmetic
  ;; =========================================================================

  (func $bench_integer (export "bench_integer") (param $iters i64) (result f64)
    (local $i i64)
    (local $acc i64)
    (local $mul i64)
    (local $add i64)
    (local $t0 f64)
    (local $elapsed f64)

    (local.set $t0 (call $perf_now))
    (local.set $i (i64.const 0))
    (local.set $acc (i64.const 0x123456789ABCDEF0))
    (local.set $mul (i64.const -2401053088876216130))  ;; 0xDEADBEEFCAFEBABE
    (local.set $add (i64.const 81985529216486895))     ;; 0x0123456789ABCDEF

    (block $break
      (loop $loop
        (br_if $break (i64.ge_u (local.get $i) (local.get $iters)))

        ;; acc = acc * mul + add
        (local.set $acc
          (i64.add
            (i64.mul (local.get $acc) (local.get $mul))
            (local.get $add)
          )
        )

        ;; acc ^= acc >> 17
        (local.set $acc
          (i64.xor (local.get $acc) (i64.shr_u (local.get $acc) (i64.const 17)))
        )

        ;; acc ^= acc << 31
        (local.set $acc
          (i64.xor (local.get $acc) (i64.shl (local.get $acc) (i64.const 31)))
        )

        ;; acc ^= acc >> 43
        (local.set $acc
          (i64.xor (local.get $acc) (i64.shr_u (local.get $acc) (i64.const 43)))
        )

        (local.set $i (i64.add (local.get $i) (i64.const 1)))
        (br $loop)
      )
    )

    (global.set $result_i64 (local.get $acc))
    (local.set $elapsed (f64.sub (call $perf_now) (local.get $t0)))
    (local.get $elapsed)
  )

  ;; =========================================================================
  ;; Benchmark: Floating Point FMA
  ;; =========================================================================

  (func $bench_fma (export "bench_fma") (param $iters i64) (result f64)
    (local $i i64)
    (local $iter i64)
    (local $j i32)
    (local $a f64)
    (local $b f64)
    (local $c f64)
    (local $addr_a i32)
    (local $addr_b i32)
    (local $addr_c i32)
    (local $t0 f64)
    (local $elapsed f64)

    (local.set $t0 (call $perf_now))
    (local.set $iter (i64.const 0))

    (block $outer_break
      (loop $outer_loop
        (br_if $outer_break (i64.ge_u (local.get $iter) (local.get $iters)))

        (local.set $j (i32.const 0))

        (block $inner_break
          (loop $inner_loop
            (br_if $inner_break (i32.ge_u (local.get $j) (i32.const 1024)))

            ;; addr_a = arr_a_base + j * 8
            (local.set $addr_a
              (i32.add
                (global.get $arr_a_base)
                (i32.mul (local.get $j) (i32.const 8))
              )
            )
            (local.set $addr_b
              (i32.add
                (global.get $arr_b_base)
                (i32.mul (local.get $j) (i32.const 8))
              )
            )
            (local.set $addr_c
              (i32.add
                (global.get $arr_c_base)
                (i32.mul (local.get $j) (i32.const 8))
              )
            )

            (local.set $a (f64.load (local.get $addr_a)))
            (local.set $b (f64.load (local.get $addr_b)))
            (local.set $c (f64.load (local.get $addr_c)))

            ;; c = a * b + c  (FMA)
            (local.set $c
              (f64.add (f64.mul (local.get $a) (local.get $b)) (local.get $c))
            )

            ;; a = c * 0.5 + b
            (local.set $a
              (f64.add (f64.mul (local.get $c) (f64.const 0.5)) (local.get $b))
            )

            ;; b = a + c * 0.25
            (local.set $b
              (f64.add (local.get $a) (f64.mul (local.get $c) (f64.const 0.25)))
            )

            (f64.store (local.get $addr_a) (local.get $a))
            (f64.store (local.get $addr_b) (local.get $b))
            (f64.store (local.get $addr_c) (local.get $c))

            (local.set $j (i32.add (local.get $j) (i32.const 1)))
            (br $inner_loop)
          )
        )

        (local.set $iter (i64.add (local.get $iter) (i64.const 1)))
        (br $outer_loop)
      )
    )

    (local.set $elapsed (f64.sub (call $perf_now) (local.get $t0)))
    (local.get $elapsed)
  )

  ;; =========================================================================
  ;; Benchmark: Memory Copy
  ;; =========================================================================

  (func $bench_memcopy (export "bench_memcopy") (param $iters i64) (result f64)
    (local $i i64)
    (local $t0 f64)

    (local.set $t0 (call $perf_now))
    (local.set $i (i64.const 0))

    (block $break
      (loop $loop
        (br_if $break (i64.ge_u (local.get $i) (local.get $iters)))

        ;; Copy 8KB from arr_a to arr_c
        (memory.copy
          (global.get $arr_c_base)   ;; dst
          (global.get $arr_a_base)   ;; src
          (i32.const 8192)           ;; 8KB
        )

        (local.set $i (i64.add (local.get $i) (i64.const 1)))
        (br $loop)
      )
    )

    (f64.sub (call $perf_now) (local.get $t0))
  )

  ;; =========================================================================
  ;; Benchmark: Memory Fill
  ;; =========================================================================

  (func $bench_memfill (export "bench_memfill") (param $iters i64) (result f64)
    (local $i i64)
    (local $t0 f64)

    (local.set $t0 (call $perf_now))
    (local.set $i (i64.const 0))

    (block $break
      (loop $loop
        (br_if $break (i64.ge_u (local.get $i) (local.get $iters)))

        ;; Fill 8KB with 0xAB
        (memory.fill
          (global.get $arr_c_base)
          (i32.const 0xAB)
          (i32.const 8192)
        )

        (local.set $i (i64.add (local.get $i) (i64.const 1)))
        (br $loop)
      )
    )

    (f64.sub (call $perf_now) (local.get $t0))
  )

  ;; =========================================================================
  ;; Benchmark: Fibonacci (recursive, tests call overhead)
  ;; =========================================================================

  (func $fib (param $n i64) (result i64)
    (if (i64.le_u (local.get $n) (i64.const 1))
      (then (return (local.get $n)))
    )
    (i64.add
      (call $fib (i64.sub (local.get $n) (i64.const 1)))
      (call $fib (i64.sub (local.get $n) (i64.const 2)))
    )
  )

  (func $bench_fibonacci (export "bench_fibonacci") (param $n i64) (result i64)
    (call $fib (local.get $n))
  )

  ;; =========================================================================
  ;; Benchmark: Dot Product
  ;; =========================================================================

  (func $bench_dot_product (export "bench_dot_product") (param $iters i64) (result f64)
    (local $i i64)
    (local $j i32)
    (local $sum f64)
    (local $a f64)
    (local $b f64)
    (local $t0 f64)

    (local.set $t0 (call $perf_now))
    (local.set $i (i64.const 0))

    (block $outer_break
      (loop $outer_loop
        (br_if $outer_break (i64.ge_u (local.get $i) (local.get $iters)))

        (local.set $sum (f64.const 0.0))
        (local.set $j (i32.const 0))

        (block $inner_break
          (loop $inner_loop
            (br_if $inner_break (i32.ge_u (local.get $j) (i32.const 1024)))

            (local.set $a
              (f64.load
                (i32.add (global.get $arr_a_base) (i32.mul (local.get $j) (i32.const 8)))
              )
            )
            (local.set $b
              (f64.load
                (i32.add (global.get $arr_b_base) (i32.mul (local.get $j) (i32.const 8)))
              )
            )

            ;; sum += a * b
            (local.set $sum
              (f64.add (local.get $sum) (f64.mul (local.get $a) (local.get $b)))
            )

            (local.set $j (i32.add (local.get $j) (i32.const 1)))
            (br $inner_loop)
          )
        )

        (global.set $result_f64 (local.get $sum))
        (local.set $i (i64.add (local.get $i) (i64.const 1)))
        (br $outer_loop)
      )
    )

    (f64.sub (call $perf_now) (local.get $t0))
  )

  ;; =========================================================================
  ;; Run All Benchmarks
  ;; =========================================================================

  (func $run_all (export "run_all") (result f64)
    (local $total f64)
    (local $elapsed f64)

    ;; Initialize arrays
    (call $init_arrays)

    ;; Integer benchmark
    (local.set $elapsed (call $bench_integer (i64.const 10000000)))
    (local.set $total (f64.add (local.get $total) (local.get $elapsed)))
    (call $log_f64 (local.get $elapsed))

    ;; FMA benchmark
    (local.set $elapsed (call $bench_fma (i64.const 1000)))
    (local.set $total (f64.add (local.get $total) (local.get $elapsed)))
    (call $log_f64 (local.get $elapsed))

    ;; Memory copy benchmark
    (local.set $elapsed (call $bench_memcopy (i64.const 10000)))
    (local.set $total (f64.add (local.get $total) (local.get $elapsed)))
    (call $log_f64 (local.get $elapsed))

    ;; Memory fill benchmark
    (local.set $elapsed (call $bench_memfill (i64.const 10000)))
    (local.set $total (f64.add (local.get $total) (local.get $elapsed)))
    (call $log_f64 (local.get $elapsed))

    ;; Dot product benchmark
    (local.set $elapsed (call $bench_dot_product (i64.const 1000)))
    (local.set $total (f64.add (local.get $total) (local.get $elapsed)))
    (call $log_f64 (local.get $elapsed))

    ;; Fibonacci (n=35)
    (drop (call $bench_fibonacci (i64.const 35)))

    (local.get $total)
  )

  ;; =========================================================================
  ;; Exports
  ;; =========================================================================

  (export "bench_integer"    (func $bench_integer))
  (export "bench_fma"        (func $bench_fma))
  (export "bench_memcopy"    (func $bench_memcopy))
  (export "bench_memfill"    (func $bench_memfill))
  (export "bench_fibonacci"  (func $bench_fibonacci))
  (export "bench_dot_product" (func $bench_dot_product))
  (export "run_all"          (func $run_all))
  (export "init_arrays"      (func $init_arrays))
)
