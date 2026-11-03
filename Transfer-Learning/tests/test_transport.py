# =============================================================================
# test_transport.py
# Unit tests for the WebTransport QUIC pipeline components
# Tests WT-MAIA/1.0 protocol, stream management, and congestion control
# =============================================================================

import sys
import math
import random
import struct
import json
import time
import unittest
import hashlib
from typing import Any, Dict, List, Optional, Tuple
from dataclasses import dataclass, field
from collections import deque

# =============================================================================
# Frame Format Tests
# =============================================================================

@dataclass
class WTMAIAFrame:
    """WT-MAIA/1.0 protocol frame."""
    version: int = 1
    stream_id: int = 0
    flags: int = 0
    sequence_number: int = 0
    timestamp: int = 0
    payload: bytes = b""

    FLAG_RELIABLE = 0x0001
    FLAG_COMPRESSED = 0x0002
    FLAG_ENCRYPTED = 0x0004
    FLAG_PRIORITY_HIGH = 0x0008
    FLAG_BATCH = 0x0010
    FLAG_ACK_REQUIRED = 0x0020
    FLAG_LAST_FRAME = 0x0040
    FLAG_QUANTUM = 0x0080

    def encode(self) -> bytes:
        import zlib
        crc = zlib.crc32(self.payload) & 0xFFFFFFFF
        header = struct.pack('>BBHIIQII',
            self.version, self.stream_id, self.flags,
            self.sequence_number, 0, self.timestamp,
            len(self.payload), crc
        )
        return header + self.payload

    @classmethod
    def decode(cls, data: bytes) -> 'WTMAIAFrame':
        if len(data) < 28:
            raise ValueError(f"Frame too short: {len(data)}")
        version, stream_id, flags, seq, _, timestamp, payload_len, crc = struct.unpack('>BBHIIQII', data[:28])
        if payload_len > len(data) - 28:
            raise ValueError(f"Truncated payload: expected {payload_len}, got {len(data) - 28}")
        payload = data[28:28 + payload_len]
        import zlib
        if zlib.crc32(payload) & 0xFFFFFFFF != crc:
            raise ValueError("CRC mismatch")
        return cls(version=version, stream_id=stream_id, flags=flags,
                   sequence_number=seq, timestamp=timestamp, payload=payload)

    def is_reliable(self) -> bool:
        return bool(self.flags & self.FLAG_RELIABLE)

    def is_compressed(self) -> bool:
        return bool(self.flags & self.FLAG_COMPRESSED)

    def is_high_priority(self) -> bool:
        return bool(self.flags & self.FLAG_PRIORITY_HIGH)

    def is_quantum(self) -> bool:
        return bool(self.flags & self.FLAG_QUANTUM)


class TestFrameFormat(unittest.TestCase):
    """Tests for WT-MAIA/1.0 frame format."""

    def test_frame_encode_decode_roundtrip(self):
        """Frame should survive encode/decode roundtrip."""
        payload = b'{"sensor_id": 42, "coherence": 0.98}'
        frame = WTMAIAFrame(
            version=1, stream_id=0, flags=0x0001,
            sequence_number=12345, timestamp=1000000,
            payload=payload
        )
        encoded = frame.encode()
        decoded = WTMAIAFrame.decode(encoded)

        self.assertEqual(decoded.version, frame.version)
        self.assertEqual(decoded.stream_id, frame.stream_id)
        self.assertEqual(decoded.flags, frame.flags)
        self.assertEqual(decoded.sequence_number, frame.sequence_number)
        self.assertEqual(decoded.timestamp, frame.timestamp)
        self.assertEqual(decoded.payload, frame.payload)

    def test_frame_header_size(self):
        """Frame header should be exactly 28 bytes."""
        frame = WTMAIAFrame(payload=b"test")
        encoded = frame.encode()
        self.assertEqual(len(encoded), 28 + 4)  # 28 header + 4 payload

    def test_empty_payload_frame(self):
        """Frame with empty payload should encode/decode correctly."""
        frame = WTMAIAFrame(payload=b"")
        encoded = frame.encode()
        decoded = WTMAIAFrame.decode(encoded)
        self.assertEqual(decoded.payload, b"")

    def test_large_payload_frame(self):
        """Frame with large payload should encode/decode correctly."""
        payload = b"x" * 65536
        frame = WTMAIAFrame(payload=payload)
        encoded = frame.encode()
        decoded = WTMAIAFrame.decode(encoded)
        self.assertEqual(decoded.payload, payload)

    def test_flag_reliable(self):
        """FLAG_RELIABLE should be detectable."""
        frame = WTMAIAFrame(flags=WTMAIAFrame.FLAG_RELIABLE)
        self.assertTrue(frame.is_reliable())
        frame2 = WTMAIAFrame(flags=0)
        self.assertFalse(frame2.is_reliable())

    def test_flag_compressed(self):
        """FLAG_COMPRESSED should be detectable."""
        frame = WTMAIAFrame(flags=WTMAIAFrame.FLAG_COMPRESSED)
        self.assertTrue(frame.is_compressed())

    def test_flag_high_priority(self):
        """FLAG_PRIORITY_HIGH should be detectable."""
        frame = WTMAIAFrame(flags=WTMAIAFrame.FLAG_PRIORITY_HIGH)
        self.assertTrue(frame.is_high_priority())

    def test_flag_quantum(self):
        """FLAG_QUANTUM should be detectable."""
        frame = WTMAIAFrame(flags=WTMAIAFrame.FLAG_QUANTUM)
        self.assertTrue(frame.is_quantum())

    def test_multiple_flags(self):
        """Multiple flags should be combinable."""
        flags = WTMAIAFrame.FLAG_RELIABLE | WTMAIAFrame.FLAG_COMPRESSED | WTMAIAFrame.FLAG_PRIORITY_HIGH
        frame = WTMAIAFrame(flags=flags)
        self.assertTrue(frame.is_reliable())
        self.assertTrue(frame.is_compressed())
        self.assertTrue(frame.is_high_priority())
        self.assertFalse(frame.is_quantum())

    def test_sequence_number_wraps(self):
        """Sequence number should wrap at 2^32."""
        max_seq = 2**32 - 1
        frame = WTMAIAFrame(sequence_number=max_seq)
        encoded = frame.encode()
        decoded = WTMAIAFrame.decode(encoded)
        self.assertEqual(decoded.sequence_number, max_seq)

    def test_frame_too_short_raises(self):
        """Decoding frame shorter than header should raise ValueError."""
        with self.assertRaises(ValueError):
            WTMAIAFrame.decode(b"too short")

    def test_payload_integrity(self):
        """Payload should be preserved exactly."""
        for size in [0, 1, 100, 1000, 10000]:
            payload = bytes(range(size % 256)) * (size // 256 + 1)
            payload = payload[:size]
            frame = WTMAIAFrame(payload=payload)
            decoded = WTMAIAFrame.decode(frame.encode())
            self.assertEqual(decoded.payload, payload)


# =============================================================================
# Stream Management Tests
# =============================================================================

@dataclass
class StreamState:
    """State of a QUIC stream."""
    stream_id: int
    priority: int
    is_open: bool = True
    bytes_sent: int = 0
    bytes_received: int = 0
    frames_sent: int = 0
    frames_received: int = 0
    sequence_number: int = 0
    flow_window: int = 10 * 1024 * 1024  # 10 MB
    max_frame_size: int = 65536


class StreamManager:
    """Manages QUIC streams."""

    STREAM_PRIORITIES = {0: 0, 1: 1, 2: 1, 3: 6, 4: 0, 5: 3, 6: 3, 7: 5, 8: 0, 9: 2}
    MAX_FRAME_SIZES = {
        0: 4096, 1: 65536, 2: 131072, 3: 512, 4: 2048,
        5: 32768, 6: 16384, 7: 1024, 8: 65536, 9: 262144
    }

    def __init__(self):
        self.streams: Dict[int, StreamState] = {}
        self.send_queues: Dict[int, deque] = {}

    def open_stream(self, stream_id: int) -> bool:
        priority = self.STREAM_PRIORITIES.get(stream_id, 3)
        max_size = self.MAX_FRAME_SIZES.get(stream_id, 65536)
        self.streams[stream_id] = StreamState(stream_id, priority, max_frame_size=max_size)
        self.send_queues[stream_id] = deque(maxlen=1000)
        return True

    def close_stream(self, stream_id: int) -> None:
        if stream_id in self.streams:
            self.streams[stream_id].is_open = False

    def can_send(self, stream_id: int, frame_size: int) -> bool:
        s = self.streams.get(stream_id)
        if not s or not s.is_open:
            return False
        return frame_size <= s.max_frame_size and frame_size <= s.flow_window

    def send_frame(self, stream_id: int, payload: bytes, flags: int = 0) -> Optional[WTMAIAFrame]:
        if not self.can_send(stream_id, len(payload)):
            return None
        s = self.streams[stream_id]
        frame = WTMAIAFrame(
            stream_id=stream_id, flags=flags,
            sequence_number=s.sequence_number,
            timestamp=int(time.time() * 1e6),
            payload=payload
        )
        s.sequence_number = (s.sequence_number + 1) % 2**32
        s.bytes_sent += len(payload)
        s.frames_sent += 1
        s.flow_window -= len(payload)
        self.send_queues[stream_id].append(frame)
        return frame

    def receive_frame(self, frame: WTMAIAFrame) -> None:
        s = self.streams.get(frame.stream_id)
        if s:
            s.bytes_received += len(frame.payload)
            s.frames_received += 1
            s.flow_window = min(10 * 1024 * 1024, s.flow_window + len(frame.payload))


class TestStreamManagement(unittest.TestCase):
    """Tests for QUIC stream management."""

    def setUp(self):
        self.manager = StreamManager()
        for i in range(10):
            self.manager.open_stream(i)

    def test_all_streams_open(self):
        """All 10 streams should be open after initialization."""
        for i in range(10):
            self.assertIn(i, self.manager.streams)
            self.assertTrue(self.manager.streams[i].is_open)

    def test_stream_priorities_correct(self):
        """Stream priorities should match WT-MAIA/1.0 spec."""
        expected = {0: 0, 1: 1, 2: 1, 3: 6, 4: 0, 5: 3, 6: 3, 7: 5, 8: 0, 9: 2}
        for stream_id, priority in expected.items():
            self.assertEqual(self.manager.streams[stream_id].priority, priority)

    def test_critical_streams_highest_priority(self):
        """Streams 0, 4, 8 should have highest priority (0)."""
        for stream_id in [0, 4, 8]:
            self.assertEqual(self.manager.streams[stream_id].priority, 0)

    def test_telemetry_lowest_priority(self):
        """Stream 3 (telemetry) should have lowest priority."""
        self.assertEqual(self.manager.streams[3].priority, 6)

    def test_send_frame_updates_stats(self):
        """Sending frame should update stream statistics."""
        payload = b"test payload"
        frame = self.manager.send_frame(0, payload)
        self.assertIsNotNone(frame)
        self.assertEqual(self.manager.streams[0].bytes_sent, len(payload))
        self.assertEqual(self.manager.streams[0].frames_sent, 1)

    def test_sequence_number_increments(self):
        """Sequence number should increment with each frame."""
        for i in range(5):
            frame = self.manager.send_frame(0, b"test")
            self.assertEqual(frame.sequence_number, i)

    def test_sequence_number_wraps(self):
        """Sequence number should wrap at 2^32."""
        self.manager.streams[0].sequence_number = 2**32 - 1
        frame = self.manager.send_frame(0, b"test")
        self.assertEqual(frame.sequence_number, 2**32 - 1)
        frame2 = self.manager.send_frame(0, b"test")
        self.assertEqual(frame2.sequence_number, 0)

    def test_frame_too_large_rejected(self):
        """Frame larger than max_frame_size should be rejected."""
        stream_id = 3  # Telemetry: max 512 bytes
        large_payload = b"x" * 1000
        frame = self.manager.send_frame(stream_id, large_payload)
        self.assertIsNone(frame)

    def test_closed_stream_rejects_frames(self):
        """Closed stream should reject frame sends."""
        self.manager.close_stream(0)
        frame = self.manager.send_frame(0, b"test")
        self.assertIsNone(frame)

    def test_receive_frame_updates_stats(self):
        """Receiving frame should update stream statistics."""
        frame = WTMAIAFrame(stream_id=2, payload=b"weight delta data")
        self.manager.receive_frame(frame)
        self.assertEqual(self.manager.streams[2].bytes_received, len(frame.payload))
        self.assertEqual(self.manager.streams[2].frames_received, 1)

    def test_flow_window_decreases_on_send(self):
        """Flow window should decrease when frames are sent."""
        initial_window = self.manager.streams[0].flow_window
        payload = b"x" * 1000
        self.manager.send_frame(0, payload)
        self.assertEqual(self.manager.streams[0].flow_window, initial_window - 1000)

    def test_flow_window_increases_on_receive(self):
        """Flow window should increase when frames are received."""
        self.manager.streams[0].flow_window = 5000
        frame = WTMAIAFrame(stream_id=0, payload=b"x" * 1000)
        self.manager.receive_frame(frame)
        self.assertGreater(self.manager.streams[0].flow_window, 5000)

    def test_priority_ordering(self):
        """Streams should be orderable by priority."""
        priorities = [(sid, s.priority) for sid, s in self.manager.streams.items()]
        sorted_by_priority = sorted(priorities, key=lambda x: x[1])
        # Lowest priority number = highest priority
        self.assertEqual(sorted_by_priority[0][1], 0)


# =============================================================================
# Congestion Control Tests
# =============================================================================

@dataclass
class CongestionState:
    """CUBIC congestion control state."""
    cwnd: float = 10.0
    ssthresh: float = 10000.0
    in_slow_start: bool = True
    rtt: float = 0.0
    min_rtt: float = float('inf')
    smoothed_rtt: float = 0.0
    rtt_variance: float = 0.0
    packet_loss: float = 0.0
    bytes_in_flight: int = 0
    total_bytes_sent: int = 0
    total_lost: int = 0
    total_retransmit: int = 0
    cubic_w_max: float = 10.0
    cubic_epoch_start: float = 0.0


def update_rtt(state: CongestionState, measured_rtt: float) -> CongestionState:
    """Update RTT estimates using RFC 6298."""
    alpha, beta = 0.125, 0.25
    if state.smoothed_rtt == 0.0:
        state.smoothed_rtt = measured_rtt
        state.rtt_variance = measured_rtt / 2.0
    else:
        state.rtt_variance = (1 - beta) * state.rtt_variance + beta * abs(measured_rtt - state.smoothed_rtt)
        state.smoothed_rtt = (1 - alpha) * state.smoothed_rtt + alpha * measured_rtt
    state.min_rtt = min(state.min_rtt, measured_rtt)
    state.rtt = measured_rtt
    return state


def cubic_on_ack(state: CongestionState, acked_bytes: int, current_time: float) -> CongestionState:
    """CUBIC congestion window update on ACK."""
    mss = 1460
    if state.in_slow_start:
        state.cwnd += acked_bytes / mss
        if state.cwnd >= state.ssthresh:
            state.in_slow_start = False
    else:
        beta = 0.7
        c = 0.4
        t = current_time - state.cubic_epoch_start
        k = (state.cubic_w_max * (1 - beta) / c) ** (1/3)
        w_cubic = c * (t - k) ** 3 + state.cubic_w_max
        w_tcp = state.cubic_w_max * beta + 3 * beta / (2 - beta) * acked_bytes / mss
        state.cwnd = min(10000, max(w_cubic, w_tcp))
    state.bytes_in_flight = max(0, state.bytes_in_flight - acked_bytes)
    state.total_bytes_sent += acked_bytes
    return state


def cubic_on_loss(state: CongestionState, lost_bytes: int, current_time: float) -> CongestionState:
    """CUBIC congestion window update on loss."""
    beta = 0.7
    state.cubic_w_max = state.cwnd
    state.ssthresh = max(2.0, state.cwnd * beta)
    state.cwnd = state.ssthresh
    state.in_slow_start = False
    state.cubic_epoch_start = current_time
    state.total_lost += lost_bytes
    state.total_retransmit += 1
    state.packet_loss = state.total_lost / max(1, state.total_bytes_sent)
    return state


class TestCongestionControl(unittest.TestCase):
    """Tests for CUBIC congestion control."""

    def test_slow_start_exponential_growth(self):
        """CWND should grow exponentially in slow start."""
        state = CongestionState()
        mss = 1460
        initial_cwnd = state.cwnd

        for _ in range(10):
            state = cubic_on_ack(state, int(state.cwnd * mss), time.time())

        # Should have grown significantly
        self.assertGreater(state.cwnd, initial_cwnd * 5)

    def test_slow_start_exits_at_ssthresh(self):
        """Slow start should exit when CWND reaches ssthresh."""
        state = CongestionState(ssthresh=20.0)
        mss = 1460

        for _ in range(100):
            state = cubic_on_ack(state, mss, time.time())
            if not state.in_slow_start:
                break

        self.assertFalse(state.in_slow_start)

    def test_loss_reduces_cwnd(self):
        """Packet loss should reduce CWND."""
        state = CongestionState(cwnd=100.0, in_slow_start=False)
        cwnd_before = state.cwnd
        state = cubic_on_loss(state, 1460, time.time())
        self.assertLess(state.cwnd, cwnd_before)

    def test_loss_sets_ssthresh(self):
        """Loss should set ssthresh to fraction of CWND."""
        state = CongestionState(cwnd=100.0, in_slow_start=False)
        state = cubic_on_loss(state, 1460, time.time())
        self.assertAlmostEqual(state.ssthresh, 100.0 * 0.7, delta=1.0)

    def test_rtt_smoothing(self):
        """Smoothed RTT should converge to true RTT."""
        state = CongestionState()
        true_rtt = 10.0

        for _ in range(100):
            measured = true_rtt + random.gauss(0, 0.5)
            state = update_rtt(state, measured)

        self.assertAlmostEqual(state.smoothed_rtt, true_rtt, delta=1.0)

    def test_min_rtt_tracking(self):
        """Min RTT should track minimum observed RTT."""
        state = CongestionState()
        rtts = [10.0, 5.0, 15.0, 8.0, 20.0, 3.0, 12.0]
        for rtt in rtts:
            state = update_rtt(state, rtt)
        self.assertAlmostEqual(state.min_rtt, 3.0, delta=0.01)

    def test_rto_computation(self):
        """RTO should be SRTT + 4*RTTVAR."""
        state = CongestionState(smoothed_rtt=10.0, rtt_variance=2.0)
        rto = state.smoothed_rtt + 4 * state.rtt_variance
        self.assertAlmostEqual(rto, 18.0, delta=0.01)

    def test_cwnd_non_negative(self):
        """CWND should never go negative."""
        state = CongestionState(cwnd=2.0)
        for _ in range(100):
            state = cubic_on_loss(state, 1460, time.time())
        self.assertGreater(state.cwnd, 0)

    def test_packet_loss_rate_computation(self):
        """Packet loss rate should be in [0, 1]."""
        state = CongestionState()
        state.total_bytes_sent = 10000
        state.total_lost = 100
        state.packet_loss = state.total_lost / state.total_bytes_sent
        self.assertGreaterEqual(state.packet_loss, 0.0)
        self.assertLessEqual(state.packet_loss, 1.0)

    def test_bytes_in_flight_tracking(self):
        """Bytes in flight should track correctly."""
        state = CongestionState()
        state.bytes_in_flight = 1000
        state = cubic_on_ack(state, 500, time.time())
        self.assertEqual(state.bytes_in_flight, 500)


# =============================================================================
# Bandwidth Allocation Tests
# =============================================================================

class TestBandwidthAllocation(unittest.TestCase):
    """Tests for priority-aware bandwidth allocation."""

    def setUp(self):
        self.total_bw = 1000.0  # Mbps
        self.allocations = {
            'critical': 0.40,
            'high': 0.30,
            'medium': 0.20,
            'low': 0.10,
        }

    def test_allocations_sum_to_one(self):
        """Bandwidth allocations should sum to 1.0."""
        total = sum(self.allocations.values())
        self.assertAlmostEqual(total, 1.0, places=10)

    def test_critical_streams_get_most_bandwidth(self):
        """Critical streams should get the most bandwidth."""
        self.assertGreater(self.allocations['critical'], self.allocations['high'])
        self.assertGreater(self.allocations['high'], self.allocations['medium'])
        self.assertGreater(self.allocations['medium'], self.allocations['low'])

    def test_stream_bandwidth_positive(self):
        """Each stream should get positive bandwidth."""
        stream_bw = {
            0: self.total_bw * self.allocations['critical'] / 3,
            1: self.total_bw * self.allocations['high'] / 3,
            2: self.total_bw * self.allocations['high'] / 3,
            3: self.total_bw * self.allocations['low'] / 2,
            4: self.total_bw * self.allocations['critical'] / 3,
            5: self.total_bw * self.allocations['medium'] / 2,
            6: self.total_bw * self.allocations['medium'] / 2,
            7: self.total_bw * self.allocations['low'] / 2,
            8: self.total_bw * self.allocations['critical'] / 3,
            9: self.total_bw * self.allocations['high'] / 3,
        }
        for stream_id, bw in stream_bw.items():
            self.assertGreater(bw, 0)

    def test_congestion_reduces_non_critical_bandwidth(self):
        """During congestion, non-critical streams should get less bandwidth."""
        normal_bw = {i: self.total_bw / 10 for i in range(10)}
        congestion_factor = 0.5

        congested_bw = {}
        for i in range(10):
            if i in [0, 4, 8]:  # Critical
                congested_bw[i] = normal_bw[i]
            else:
                congested_bw[i] = normal_bw[i] * congestion_factor

        # Critical streams unchanged
        for i in [0, 4, 8]:
            self.assertEqual(congested_bw[i], normal_bw[i])

        # Non-critical streams reduced
        for i in [1, 2, 3, 5, 6, 7, 9]:
            self.assertLess(congested_bw[i], normal_bw[i])


# =============================================================================
# Session Management Tests
# =============================================================================

@dataclass
class SessionState:
    """WebTransport session state."""
    session_id: str
    node_id: str
    peer_address: str
    is_connected: bool = True
    rtt_ms: float = 0.0
    bandwidth_mbps: float = 0.0
    packet_loss: float = 0.0
    total_bytes_sent: int = 0
    total_bytes_received: int = 0
    connected_at: float = field(default_factory=time.time)
    last_heartbeat: float = field(default_factory=time.time)


class TestSessionManagement(unittest.TestCase):
    """Tests for WebTransport session management."""

    def test_session_creation(self):
        """Session should be created with correct attributes."""
        session = SessionState(
            session_id="test_session_001",
            node_id="windows_node_0",
            peer_address="192.168.1.20"
        )
        self.assertEqual(session.session_id, "test_session_001")
        self.assertEqual(session.node_id, "windows_node_0")
        self.assertTrue(session.is_connected)

    def test_session_timeout_detection(self):
        """Session should be detectable as timed out."""
        session = SessionState(
            session_id="test", node_id="node", peer_address="addr"
        )
        session.last_heartbeat = time.time() - 100  # 100 seconds ago
        timeout_ms = 30000  # 30 seconds

        is_timed_out = (time.time() - session.last_heartbeat) * 1000 > timeout_ms
        self.assertTrue(is_timed_out)

    def test_session_alive_detection(self):
        """Recent heartbeat should indicate alive session."""
        session = SessionState(
            session_id="test", node_id="node", peer_address="addr"
        )
        session.last_heartbeat = time.time()
        timeout_ms = 30000

        is_alive = (time.time() - session.last_heartbeat) * 1000 < timeout_ms
        self.assertTrue(is_alive)

    def test_throughput_computation(self):
        """Throughput should be computed correctly."""
        session = SessionState(
            session_id="test", node_id="node", peer_address="addr"
        )
        session.total_bytes_sent = 1000000  # 1 MB
        session.total_bytes_received = 500000  # 0.5 MB
        duration_ms = 1000  # 1 second

        total_bytes = session.total_bytes_sent + session.total_bytes_received
        throughput_mbps = total_bytes * 8 / duration_ms / 1000
        self.assertAlmostEqual(throughput_mbps, 12.0, delta=0.1)

    def test_multiple_sessions_independent(self):
        """Multiple sessions should be independent."""
        sessions = [
            SessionState(session_id=f"session_{i}", node_id=f"node_{i}", peer_address=f"addr_{i}")
            for i in range(10)
        ]
        for i, session in enumerate(sessions):
            session.total_bytes_sent = i * 1000

        for i, session in enumerate(sessions):
            self.assertEqual(session.total_bytes_sent, i * 1000)


# =============================================================================
# Protocol Payload Tests
# =============================================================================

class TestProtocolPayloads(unittest.TestCase):
    """Tests for WT-MAIA/1.0 protocol payload formats."""

    def test_sensor_data_payload_valid_json(self):
        """Sensor data payload should be valid JSON."""
        payload = {
            'sensor_id': 42,
            'coherence': 0.98,
            'phase': 1.24,
            'adc': 42155,
            'timestamp': 1887822,
            'node_id': 'windows_node_0',
            'batch_seq': 100,
            'checksum': 12345678,
        }
        json_str = json.dumps(payload)
        parsed = json.loads(json_str)
        self.assertEqual(parsed['sensor_id'], 42)
        self.assertAlmostEqual(parsed['coherence'], 0.98)

    def test_gradient_payload_valid_json(self):
        """Gradient update payload should be valid JSON."""
        payload = {
            'model': 'siamese',
            'layer': 'attention_4',
            'gradient_hash': 'ABCD1234',
            'topk': 0.10,
            'step': 1000,
            'node_id': 'windows_node_0',
            'sparsity': 0.9,
        }
        json_str = json.dumps(payload)
        parsed = json.loads(json_str)
        self.assertEqual(parsed['model'], 'siamese')
        self.assertAlmostEqual(parsed['topk'], 0.10)

    def test_replay_cluster_payload_valid_json(self):
        """Replay cluster payload should be valid JSON."""
        payload = {
            'cluster': 14,
            'samples': 258,
            'mean_hamming': 17.0,
            'threshold': 24,
            'novelty_score': 0.75,
            'timestamp': 1887822,
        }
        json_str = json.dumps(payload)
        parsed = json.loads(json_str)
        self.assertEqual(parsed['cluster'], 14)
        self.assertEqual(parsed['samples'], 258)

    def test_fisher_payload_valid_json(self):
        """Fisher information payload should be valid JSON."""
        payload = {
            'fisher_norm': 221.4,
            'lambda': 400.0,
            'task_id': 3,
            'layer': 'attention_4',
            'timestamp': 1887822,
        }
        json_str = json.dumps(payload)
        parsed = json.loads(json_str)
        self.assertAlmostEqual(parsed['fisher_norm'], 221.4)

    def test_maia_inference_payload_valid_json(self):
        """MAIA inference payload should be valid JSON."""
        payload = {
            'request_id': 774,
            'model_version': '1.0',
            'batch_size': 1,
            'timestamp': 1887822,
            'priority': 1,
        }
        json_str = json.dumps(payload)
        parsed = json.loads(json_str)
        self.assertEqual(parsed['request_id'], 774)

    def test_blockchain_payload_valid_json(self):
        """Blockchain hash payload should be valid JSON."""
        payload = {
            'block': 115,
            'sha256': 'a' * 64,
            'prev_hash': 'b' * 64,
            'merkle_root': 'c' * 64,
            'timestamp': 1887822,
            'node_id': 'linux_node_0',
        }
        json_str = json.dumps(payload)
        parsed = json.loads(json_str)
        self.assertEqual(parsed['block'], 115)
        self.assertEqual(len(parsed['sha256']), 64)

    def test_anchor_payload_valid_json(self):
        """Majorana anchor payload should be valid JSON."""
        payload = {
            'anchor_id': 'A1',
            'alignment': 0.992,
            'phase': 0.05,
            'fidelity': 0.996,
            'error_rate': 0.001,
            'timestamp': 1887822,
        }
        json_str = json.dumps(payload)
        parsed = json.loads(json_str)
        self.assertAlmostEqual(parsed['alignment'], 0.992)


# =============================================================================
# Integration Tests
# =============================================================================

class TestTransportIntegration(unittest.TestCase):
    """Integration tests for the transport pipeline."""

    def test_full_frame_pipeline(self):
        """Test complete frame creation, transmission, and reception."""
        manager = StreamManager()
        for i in range(10):
            manager.open_stream(i)

        # Send sensor data
        sensor_payload = json.dumps({
            'sensor_id': 42, 'coherence': 0.98,
            'phase': 1.24, 'adc': 42155, 'timestamp': 1000000
        }).encode()

        frame = manager.send_frame(0, sensor_payload, WTMAIAFrame.FLAG_RELIABLE)
        self.assertIsNotNone(frame)

        # Encode and decode
        encoded = frame.encode()
        decoded = WTMAIAFrame.decode(encoded)
        self.assertEqual(decoded.payload, sensor_payload)

        # Receive on Linux side
        manager.receive_frame(decoded)
        self.assertEqual(manager.streams[0].frames_received, 1)

    def test_multi_stream_transmission(self):
        """Test simultaneous transmission on multiple streams."""
        manager = StreamManager()
        for i in range(10):
            manager.open_stream(i)

        payloads = {
            0: b"sensor_data",
            1: b"gradient_update",
            4: b"anchor_data",
            8: b"maia_inference",
        }

        frames = {}
        for stream_id, payload in payloads.items():
            frame = manager.send_frame(stream_id, payload)
            if frame:
                frames[stream_id] = frame

        # All critical streams should have sent frames
        for stream_id in [0, 4, 8]:
            self.assertIn(stream_id, frames)

    def test_congestion_affects_throughput(self):
        """Congestion should reduce effective throughput."""
        state = CongestionState(cwnd=100.0, in_slow_start=False)

        # Normal throughput
        normal_cwnd = state.cwnd

        # Simulate loss event
        state = cubic_on_loss(state, 1460, time.time())
        congested_cwnd = state.cwnd

        self.assertLess(congested_cwnd, normal_cwnd)

    def test_session_lifecycle(self):
        """Test complete session lifecycle."""
        session = SessionState(
            session_id="lifecycle_test",
            node_id="windows_node_0",
            peer_address="192.168.1.20"
        )

        # Session should be connected
        self.assertTrue(session.is_connected)

        # Simulate data transfer
        session.total_bytes_sent += 1000000
        session.total_bytes_received += 500000

        # Disconnect
        session.is_connected = False
        self.assertFalse(session.is_connected)

        # Verify stats preserved
        self.assertEqual(session.total_bytes_sent, 1000000)


# =============================================================================
# Performance Tests
# =============================================================================

class TestTransportPerformance(unittest.TestCase):
    """Performance tests for transport pipeline."""

    def test_frame_encode_decode_throughput(self):
        """Test frame encode/decode throughput."""
        payload = b"x" * 1000
        n_frames = 10000

        start = time.perf_counter()
        for i in range(n_frames):
            frame = WTMAIAFrame(stream_id=0, sequence_number=i, payload=payload)
            encoded = frame.encode()
            WTMAIAFrame.decode(encoded)
        elapsed = time.perf_counter() - start

        throughput = n_frames / elapsed
        # Should process at least 1000 frames/second
        self.assertGreater(throughput, 1000)

    def test_stream_manager_throughput(self):
        """Test stream manager frame sending throughput."""
        manager = StreamManager()
        for i in range(10):
            manager.open_stream(i)

        payload = b"x" * 100
        n_frames = 1000

        start = time.perf_counter()
        for i in range(n_frames):
            manager.send_frame(0, payload)
            # Reset flow window periodically
            if i % 100 == 0:
                manager.streams[0].flow_window = 10 * 1024 * 1024
        elapsed = time.perf_counter() - start

        throughput = n_frames / elapsed
        self.assertGreater(throughput, 1000)


# =============================================================================
# Main Test Runner
# =============================================================================

def run_all_tests():
    """Run all transport test suites."""
    test_suites = [
        unittest.TestLoader().loadTestsFromTestCase(TestFrameFormat),
        unittest.TestLoader().loadTestsFromTestCase(TestStreamManagement),
        unittest.TestLoader().loadTestsFromTestCase(TestCongestionControl),
        unittest.TestLoader().loadTestsFromTestCase(TestBandwidthAllocation),
        unittest.TestLoader().loadTestsFromTestCase(TestSessionManagement),
        unittest.TestLoader().loadTestsFromTestCase(TestProtocolPayloads),
        unittest.TestLoader().loadTestsFromTestCase(TestTransportIntegration),
        unittest.TestLoader().loadTestsFromTestCase(TestTransportPerformance),
    ]

    combined = unittest.TestSuite(test_suites)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(combined)
    return result.wasSuccessful()


if __name__ == '__main__':
    success = run_all_tests()
    sys.exit(0 if success else 1)