// =============================================================================
// Arrays.qs — Array utilities for quantum circuits and LLM tensors
// =============================================================================

namespace WindowsAGI.QuantumSDK.Arrays {

    import Std.Arrays.*;
    import Std.Convert.*;
    import Std.Math.*;

    // ─────────────────────────────────────────────────────────────────────────
    // Integer array utilities
    // ─────────────────────────────────────────────────────────────────────────
    function IntArraySum(arr : Int[]) : Int {
        mutable total = 0;
        for v in arr { set total += v; }
        return total;
    }

    function IntArrayMax(arr : Int[]) : Int {
        if Length(arr) == 0 { fail "IntArrayMax: empty array."; }
        mutable m = arr[0];
        for v in arr { if v > m { set m = v; } }
        return m;
    }

    function IntArrayMin(arr : Int[]) : Int {
        if Length(arr) == 0 { fail "IntArrayMin: empty array."; }
        mutable m = arr[0];
        for v in arr { if v < m { set m = v; } }
        return m;
    }

    function IntArrayMean(arr : Int[]) : Double {
        if Length(arr) == 0 { fail "IntArrayMean: empty array."; }
        return IntAsDouble(IntArraySum(arr)) / IntAsDouble(Length(arr));
    }

    function IntArrayContains(arr : Int[], value : Int) : Bool {
        for v in arr { if v == value { return true; } }
        return false;
    }

    function IntArrayUnique(arr : Int[]) : Int[] {
        mutable result = [];
        for v in arr {
            if not IntArrayContains(result, v) {
                set result += [v];
            }
        }
        return result;
    }

    function IntArrayReverse(arr : Int[]) : Int[] {
        let n = Length(arr);
        mutable result = arr;
        for i in 0..n / 2 - 1 {
            let tmp = result[i];
            set result w/= i <- result[n - 1 - i];
            set result w/= n - 1 - i <- tmp;
        }
        return result;
    }

    function IntArraySlice(arr : Int[], start : Int, stop : Int) : Int[] {
        if start < 0 or stop > Length(arr) or start >= stop {
            fail $"IntArraySlice: invalid range [{start}, {stop}) for array of length {Length(arr)}.";
        }
        mutable result = [];
        for i in start..stop - 1 { set result += [arr[i]]; }
        return result;
    }

    function IntArrayZeros(n : Int) : Int[] {
        mutable result = [];
        for _ in 0..n - 1 { set result += [0]; }
        return result;
    }

    function IntArrayOnes(n : Int) : Int[] {
        mutable result = [];
        for _ in 0..n - 1 { set result += [1]; }
        return result;
    }

    function IntArrayRange(start : Int, stop : Int, step : Int) : Int[] {
        if step == 0 { fail "IntArrayRange: step cannot be zero."; }
        mutable result = [];
        mutable i = start;
        while (step > 0 and i < stop) or (step < 0 and i > stop) {
            set result += [i];
            set i += step;
        }
        return result;
    }

    function IntArrayDot(a : Int[], b : Int[]) : Int {
        if Length(a) != Length(b) {
            fail $"IntArrayDot: length mismatch {Length(a)} vs {Length(b)}.";
        }
        mutable total = 0;
        for i in 0..Length(a) - 1 { set total += a[i] * b[i]; }
        return total;
    }

    function IntArrayXOR(a : Int[], b : Int[]) : Int[] {
        if Length(a) != Length(b) {
            fail $"IntArrayXOR: length mismatch {Length(a)} vs {Length(b)}.";
        }
        mutable result = [];
        for i in 0..Length(a) - 1 { set result += [a[i] ^^^ b[i]]; }
        return result;
    }

    function IntArrayAND(a : Int[], b : Int[]) : Int[] {
        if Length(a) != Length(b) {
            fail $"IntArrayAND: length mismatch {Length(a)} vs {Length(b)}.";
        }
        mutable result = [];
        for i in 0..Length(a) - 1 { set result += [a[i] &&& b[i]]; }
        return result;
    }

    function IntArrayOR(a : Int[], b : Int[]) : Int[] {
        if Length(a) != Length(b) {
            fail $"IntArrayOR: length mismatch {Length(a)} vs {Length(b)}.";
        }
        mutable result = [];
        for i in 0..Length(a) - 1 { set result += [a[i] ||| b[i]]; }
        return result;
    }

    function IntArrayHammingWeight(arr : Int[]) : Int {
        mutable count = 0;
        for v in arr { if v != 0 { set count += 1; } }
        return count;
    }

    function IntArrayHammingDistance(a : Int[], b : Int[]) : Int {
        return IntArrayHammingWeight(IntArrayXOR(a, b));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Double array utilities
    // ─────────────────────────────────────────────────────────────────────────
    function DoubleArraySum(arr : Double[]) : Double {
        mutable total = 0.0;
        for v in arr { set total += v; }
        return total;
    }

    function DoubleArrayMax(arr : Double[]) : Double {
        if Length(arr) == 0 { fail "DoubleArrayMax: empty array."; }
        mutable m = arr[0];
        for v in arr { if v > m { set m = v; } }
        return m;
    }

    function DoubleArrayMin(arr : Double[]) : Double {
        if Length(arr) == 0 { fail "DoubleArrayMin: empty array."; }
        mutable m = arr[0];
        for v in arr { if v < m { set m = v; } }
        return m;
    }

    function DoubleArrayMean(arr : Double[]) : Double {
        if Length(arr) == 0 { fail "DoubleArrayMean: empty array."; }
        return DoubleArraySum(arr) / IntAsDouble(Length(arr));
    }

    function DoubleArrayVariance(arr : Double[]) : Double {
        if Length(arr) < 2 { fail "DoubleArrayVariance: need at least 2 elements."; }
        let mean = DoubleArrayMean(arr);
        mutable sumSq = 0.0;
        for v in arr { set sumSq += (v - mean) * (v - mean); }
        return sumSq / IntAsDouble(Length(arr));
    }

    function DoubleArrayStdDev(arr : Double[]) : Double {
        return Sqrt(DoubleArrayVariance(arr));
    }

    function DoubleArrayNormalize(arr : Double[]) : Double[] {
        let s = DoubleArraySum(arr);
        if s == 0.0 { fail "DoubleArrayNormalize: sum is zero."; }
        mutable result = [];
        for v in arr { set result += [v / s]; }
        return result;
    }

    function DoubleArrayL2Norm(arr : Double[]) : Double {
        mutable sumSq = 0.0;
        for v in arr { set sumSq += v * v; }
        return Sqrt(sumSq);
    }

    function DoubleArrayL2Normalize(arr : Double[]) : Double[] {
        let norm = DoubleArrayL2Norm(arr);
        if norm == 0.0 { fail "DoubleArrayL2Normalize: zero vector."; }
        mutable result = [];
        for v in arr { set result += [v / norm]; }
        return result;
    }

    function DoubleArrayDot(a : Double[], b : Double[]) : Double {
        if Length(a) != Length(b) {
            fail $"DoubleArrayDot: length mismatch {Length(a)} vs {Length(b)}.";
        }
        mutable total = 0.0;
        for i in 0..Length(a) - 1 { set total += a[i] * b[i]; }
        return total;
    }

    function DoubleArrayAdd(a : Double[], b : Double[]) : Double[] {
        if Length(a) != Length(b) {
            fail $"DoubleArrayAdd: length mismatch {Length(a)} vs {Length(b)}.";
        }
        mutable result = [];
        for i in 0..Length(a) - 1 { set result += [a[i] + b[i]]; }
        return result;
    }

    function DoubleArrayScale(arr : Double[], scalar : Double) : Double[] {
        mutable result = [];
        for v in arr { set result += [v * scalar]; }
        return result;
    }

    function DoubleArraySoftmax(arr : Double[]) : Double[] {
        let maxVal = DoubleArrayMax(arr);
        mutable exps = [];
        for v in arr { set exps += [Exp(v - maxVal)]; }
        return DoubleArrayNormalize(exps);
    }

    function DoubleArrayArgMax(arr : Double[]) : Int {
        if Length(arr) == 0 { fail "DoubleArrayArgMax: empty array."; }
        mutable bestIdx = 0;
        mutable bestVal = arr[0];
        for i in 1..Length(arr) - 1 {
            if arr[i] > bestVal {
                set bestVal = arr[i];
                set bestIdx = i;
            }
        }
        return bestIdx;
    }

    function DoubleArrayArgMin(arr : Double[]) : Int {
        if Length(arr) == 0 { fail "DoubleArrayArgMin: empty array."; }
        mutable bestIdx = 0;
        mutable bestVal = arr[0];
        for i in 1..Length(arr) - 1 {
            if arr[i] < bestVal {
                set bestVal = arr[i];
                set bestIdx = i;
            }
        }
        return bestIdx;
    }

    function DoubleArrayClip(arr : Double[], lo : Double, hi : Double) : Double[] {
        mutable result = [];
        for v in arr {
            if v < lo { set result += [lo]; }
            elif v > hi { set result += [hi]; }
            else { set result += [v]; }
        }
        return result;
    }

    function DoubleArrayZeros(n : Int) : Double[] {
        mutable result = [];
        for _ in 0..n - 1 { set result += [0.0]; }
        return result;
    }

    function DoubleArrayOnes(n : Int) : Double[] {
        mutable result = [];
        for _ in 0..n - 1 { set result += [1.0]; }
        return result;
    }

    function DoubleArrayLinspace(start : Double, stop : Double, n : Int) : Double[] {
        if n < 2 { fail "DoubleArrayLinspace: n must be >= 2."; }
        let step = (stop - start) / IntAsDouble(n - 1);
        mutable result = [];
        for i in 0..n - 1 {
            set result += [start + IntAsDouble(i) * step];
        }
        return result;
    }

    function DoubleArrayCumSum(arr : Double[]) : Double[] {
        mutable result = [];
        mutable running = 0.0;
        for v in arr {
            set running += v;
            set result += [running];
        }
        return result;
    }

    function DoubleArrayCosineSimilarity(a : Double[], b : Double[]) : Double {
        let dot = DoubleArrayDot(a, b);
        let normA = DoubleArrayL2Norm(a);
        let normB = DoubleArrayL2Norm(b);
        if normA == 0.0 or normB == 0.0 { return 0.0; }
        return dot / (normA * normB);
    }

    function DoubleArrayKLDivergence(p : Double[], q : Double[]) : Double {
        if Length(p) != Length(q) {
            fail $"DoubleArrayKLDivergence: length mismatch {Length(p)} vs {Length(q)}.";
        }
        mutable kl = 0.0;
        for i in 0..Length(p) - 1 {
            if p[i] > 0.0 and q[i] > 0.0 {
                set kl += p[i] * Log(p[i] / q[i]);
            }
        }
        return kl;
    }

    function DoubleArrayEntropy(arr : Double[]) : Double {
        mutable h = 0.0;
        for v in arr {
            if v > 0.0 { set h -= v * Log(v); }
        }
        return h;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Syndrome / parity utilities for QEC
    // ─────────────────────────────────────────────────────────────────────────
    function ComputeParityVector(bits : Int[]) : Int[] {
        let n = Length(bits);
        mutable parity = [];
        for i in 0..n - 2 {
            set parity += [(bits[i] ^^^ bits[i + 1])];
        }
        return parity;
    }

    function ComputeGlobalParity(bits : Int[]) : Int {
        mutable p = 0;
        for b in bits { set p = p ^^^ b; }
        return p;
    }

    function IsZeroSyndrome(syndrome : Int[]) : Bool {
        for s in syndrome { if s != 0 { return false; } }
        return true;
    }

    function SyndromeWeight(syndrome : Int[]) : Int {
        mutable w = 0;
        for s in syndrome { if s != 0 { set w += 1; } }
        return w;
    }

    function FlipBit(bits : Int[], index : Int) : Int[] {
        if index < 0 or index >= Length(bits) {
            fail $"FlipBit: index {index} out of range [0, {Length(bits)}).";
        }
        mutable result = bits;
        set result w/= index <- (bits[index] ^^^ 1);
        return result;
    }

    function ApplyBitFlipCorrection(bits : Int[], errorLocations : Int[]) : Int[] {
        mutable result = bits;
        for loc in errorLocations {
            set result = FlipBit(result, loc);
        }
        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Matrix utilities (row-major flat arrays)
    // ─────────────────────────────────────────────────────────────────────────
    function MatrixGet(mat : Double[], rows : Int, cols : Int, r : Int, c : Int) : Double {
        return mat[r * cols + c];
    }

    function MatrixSet(mat : Double[], rows : Int, cols : Int, r : Int, c : Int, v : Double) : Double[] {
        mutable result = mat;
        set result w/= r * cols + c <- v;
        return result;
    }

    function MatrixMultiply(
        a    : Double[], aRows : Int, aCols : Int,
        b    : Double[], bRows : Int, bCols : Int
    ) : Double[] {
        if aCols != bRows {
            fail $"MatrixMultiply: dimension mismatch {aCols} vs {bRows}.";
        }
        mutable result = DoubleArrayZeros(aRows * bCols);
        for r in 0..aRows - 1 {
            for c in 0..bCols - 1 {
                mutable sum = 0.0;
                for k in 0..aCols - 1 {
                    set sum += MatrixGet(a, aRows, aCols, r, k) *
                               MatrixGet(b, bRows, bCols, k, c);
                }
                set result = MatrixSet(result, aRows, bCols, r, c, sum);
            }
        }
        return result;
    }

    function MatrixTranspose(mat : Double[], rows : Int, cols : Int) : Double[] {
        mutable result = DoubleArrayZeros(rows * cols);
        for r in 0..rows - 1 {
            for c in 0..cols - 1 {
                set result = MatrixSet(result, cols, rows, c, r,
                                       MatrixGet(mat, rows, cols, r, c));
            }
        }
        return result;
    }

    function MatrixIdentity(n : Int) : Double[] {
        mutable result = DoubleArrayZeros(n * n);
        for i in 0..n - 1 {
            set result = MatrixSet(result, n, n, i, i, 1.0);
        }
        return result;
    }

    function MatrixTrace(mat : Double[], n : Int) : Double {
        mutable tr = 0.0;
        for i in 0..n - 1 { set tr += MatrixGet(mat, n, n, i, i); }
        return tr;
    }

    function MatrixFrobeniusNorm(mat : Double[]) : Double {
        mutable sumSq = 0.0;
        for v in mat { set sumSq += v * v; }
        return Sqrt(sumSq);
    }
}
