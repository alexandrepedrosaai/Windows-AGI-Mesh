"""Unit tests for buffer modules."""
import math, pytest
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from src.python.buffers.ring import RingBuffer, TokenRingBuffer, FloatRingBuffer, KVCacheRingBuffer
from src.python.buffers.tensor import TensorBuffer


class TestRingBuffer:
    def test_basic_write_read(self):
        buf = RingBuffer(capacity=4)
        assert buf.write(10)
        assert buf.write(20)
        assert buf.read() == 10
        assert buf.read() == 20

    def test_capacity_enforcement(self):
        buf = RingBuffer(capacity=2)
        buf.write(1); buf.write(2)
        assert buf.is_full
        assert not buf.write(3, block=False)

    def test_empty_read_returns_none(self):
        buf = RingBuffer(capacity=4)
        assert buf.read(block=False) is None

    def test_write_many_read_many(self):
        buf = RingBuffer(capacity=10)
        written = buf.write_many([1,2,3,4,5])
        assert written == 5
        items = buf.read_many(3)
        assert items == [1,2,3]

    def test_flush(self):
        buf = RingBuffer(capacity=5)
        buf.write_many([10,20,30])
        flushed = buf.flush()
        assert flushed == [10,20,30]
        assert buf.is_empty

    def test_snapshot(self):
        buf = RingBuffer(capacity=5)
        buf.write_many([1,2,3])
        snap = buf.snapshot()
        assert snap == [1,2,3]
        assert buf.size == 3  # snapshot doesn't consume

    def test_resize(self):
        buf = RingBuffer(capacity=4)
        buf.write_many([1,2,3])
        buf.resize(8)
        assert buf.capacity == 8
        assert buf.size == 3

    def test_invalid_capacity(self):
        with pytest.raises(ValueError):
            RingBuffer(capacity=0)

    def test_peek(self):
        buf = RingBuffer(capacity=4)
        buf.write(42)
        assert buf.peek() == 42
        assert buf.size == 1  # peek doesn't consume

    def test_len(self):
        buf = RingBuffer(capacity=10)
        buf.write_many([1,2,3])
        assert len(buf) == 3


class TestTokenRingBuffer:
    def test_write_read_tokens(self):
        buf = TokenRingBuffer(capacity=100)
        buf.write_tokens([1,2,3,4,5])
        tokens = buf.read_tokens(3)
        assert tokens == [1,2,3]

    def test_to_list(self):
        buf = TokenRingBuffer(capacity=10)
        buf.write_tokens([10,20,30])
        assert buf.to_list() == [10,20,30]


class TestFloatRingBuffer:
    def test_mean(self):
        buf = FloatRingBuffer(capacity=10)
        buf.write_many([1.0, 2.0, 3.0])
        assert abs(buf.mean() - 2.0) < 1e-9

    def test_max_min(self):
        buf = FloatRingBuffer(capacity=10)
        buf.write_many([3.0, 1.0, 2.0])
        assert buf.max_val() == 3.0
        assert buf.min_val() == 1.0


class TestKVCacheRingBuffer:
    def test_write_read_kv(self):
        buf = KVCacheRingBuffer(num_heads=2, head_dim=4, max_seq_len=8)
        key   = [0.1, 0.2, 0.3, 0.4]
        value = [0.5, 0.6, 0.7, 0.8]
        buf.write_kv(0, key, value)
        k, v = buf.read_kv(0)
        assert len(k) == 4
        assert len(v) == 4

    def test_seq_len_tracking(self):
        buf = KVCacheRingBuffer(num_heads=2, head_dim=4, max_seq_len=8)
        buf.write_kv(0, [0.1]*4, [0.2]*4)
        assert buf.seq_len == 1

    def test_flush_all(self):
        buf = KVCacheRingBuffer(num_heads=2, head_dim=4, max_seq_len=8)
        buf.write_kv(0, [0.1]*4, [0.2]*4)
        buf.flush_all()
        assert buf.seq_len == 0

    def test_invalid_head_dim(self):
        buf = KVCacheRingBuffer(num_heads=2, head_dim=4, max_seq_len=8)
        with pytest.raises(ValueError):
            buf.write_kv(0, [0.1]*3, [0.2]*4)  # wrong key dim


class TestTensorBuffer:
    def test_basic_get_set(self):
        t = TensorBuffer((3, 4))
        t[1, 2] = 3.14
        assert abs(t[1, 2] - 3.14) < 1e-9

    def test_fill_zeros_ones(self):
        t = TensorBuffer((2, 3))
        t.ones()
        assert all(v == 1.0 for v in t.to_list())
        t.zeros()
        assert all(v == 0.0 for v in t.to_list())

    def test_reshape(self):
        t = TensorBuffer((2, 6))
        t.from_list(list(range(12)))
        r = t.reshape((3, 4))
        assert r.shape == (3, 4)
        assert r.size == 12

    def test_reshape_invalid(self):
        t = TensorBuffer((2, 6))
        with pytest.raises(ValueError):
            t.reshape((3, 5))

    def test_slice_dim0(self):
        t = TensorBuffer((4, 3))
        t.from_list(list(range(12)))
        s = t.slice_dim0(1, 3)
        assert s.shape == (2, 3)

    def test_add(self):
        a = TensorBuffer((3,))
        b = TensorBuffer((3,))
        a.from_list([1.0, 2.0, 3.0])
        b.from_list([4.0, 5.0, 6.0])
        a.add_(b)
        assert a.to_list() == [5.0, 7.0, 9.0]

    def test_scale(self):
        t = TensorBuffer((3,))
        t.from_list([1.0, 2.0, 3.0])
        t.scale_(2.0)
        assert t.to_list() == [2.0, 4.0, 6.0]

    def test_softmax(self):
        t = TensorBuffer((4,))
        t.from_list([1.0, 2.0, 3.0, 4.0])
        s = t.softmax()
        probs = s.to_list()
        assert abs(sum(probs) - 1.0) < 1e-9
        assert all(p > 0 for p in probs)

    def test_quantize_int8(self):
        t = TensorBuffer((4,))
        t.from_list([0.5, -0.5, 1.0, -1.0])
        data, scale, zp = t.quantize_int8()
        assert len(data) == 4
        assert scale > 0
        assert zp == 0

    def test_quantize_int4(self):
        t = TensorBuffer((4,))
        t.from_list([0.5, -0.5, 1.0, -1.0])
        data, scale, zp = t.quantize_int4()
        assert len(data) == 2  # packed 2 per byte

    def test_mean_std(self):
        t = TensorBuffer((5,))
        t.from_list([1.0, 2.0, 3.0, 4.0, 5.0])
        assert abs(t.mean() - 3.0) < 1e-9
        assert t.std() > 0

    def test_abs_max(self):
        t = TensorBuffer((3,))
        t.from_list([-5.0, 3.0, 1.0])
        assert t.abs_max() == 5.0

    def test_invalid_shape(self):
        with pytest.raises(ValueError):
            TensorBuffer((0, 3))

    def test_index_out_of_range(self):
        t = TensorBuffer((3,))
        with pytest.raises(IndexError):
            _ = t[5]

    def test_rope_embed(self):
        t = TensorBuffer((8,))
        t.from_list([1.0]*8)
        r = t.rope_embed(position=1, theta=500000.0)
        assert r.shape == (8,)
        assert len(r.to_list()) == 8

    def test_layer_norm(self):
        t = TensorBuffer((4,))
        t.from_list([1.0, 2.0, 3.0, 4.0])
        weight = [1.0]*4
        bias   = [0.0]*4
        n = t.layer_norm(weight, bias)
        vals = n.to_list()
        mean = sum(vals)/len(vals)
        assert abs(mean) < 1e-5
