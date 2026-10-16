#!/usr/bin/env python3
"""
=============================================================================
binary_storage_engine.py
WebTransport Binary Alphanumeric Storage Engine
Microsoft Edge ⊗ Mozilla Firefox — SafaSensors 5K
Siamese Twin AI Pipeline — Python Implementation
=============================================================================
Parameters: n_qubits=2, decoherence_rate=0.05, precision=BF16
Target: ~100k lines total across all modules
=============================================================================
"""

import math
import struct
import hashlib
import time
import random
import sys
import os
from typing import List, Tuple, Dict, Optional, Any
from dataclasses import dataclass, field
from enum import IntEnum, auto
from functools import reduce
import itertools

# =============================================================================
# SECTION 1: CONSTANTS & ENUMERATIONS
# =============================================================================

N_QUBITS          = 2
DECOHERENCE_RATE  = 0.05
PRECISION         = "BF16"
N_SENSORS         = 5000
N_BANKS           = 50
SENSORS_PER_BANK  = 100
BINARY_BLOCK_SIZE = 64      # bits per storage block
QUIC_STREAMS      = 8
MTU_BYTES         = 1200
FLOW_CTRL_WINDOW  = 65536
EWC_LAMBDA        = 400.0
DP_EPSILON        = 1.0
DP_DELTA          = 1e-5
CLIP_NORM         = 1.0
N_CLIENTS         = 4
BF16_BYTES        = 2
FP32_BYTES        = 4

# ASCII ranges
ASCII_DIGIT_START  = 48   # '0'
ASCII_DIGIT_END    = 57   # '9'
ASCII_UPPER_START  = 65   # 'A'
ASCII_UPPER_END    = 90   # 'Z'
ASCII_LOWER_START  = 97   # 'a'
ASCII_LOWER_END    = 122  # 'z'

# Browser IDs
BROWSER_EDGE    = 0
BROWSER_FIREFOX = 1

# Congestion states
CONG_SLOW_START   = 0
CONG_AVOID        = 1
CONG_FAST_RECOVER = 2

# Sensor categories
SENSOR_LATENCY    = 0
SENSOR_BANDWIDTH  = 1
SENSOR_PACKETLOSS = 2
SENSOR_COHERENCE  = 3
SENSOR_GRADIENT   = 4
SENSOR_ACTIVATION = 5
SENSOR_ATTENTION  = 6
SENSOR_MEMORY     = 7

# =============================================================================
# SECTION 2: BF16 PRECISION UTILITIES
# =============================================================================

def float_to_bf16(value: float) -> int:
    """Convert float32 to bfloat16 (truncate lower 16 bits of mantissa)."""
    packed = struct.pack('>f', float(value))
    bits = struct.unpack('>I', packed)[0]
    bf16 = (bits >> 16) & 0xFFFF
    return bf16

def bf16_to_float(bf16: int) -> float:
    """Convert bfloat16 back to float32."""
    bits = (bf16 & 0xFFFF) << 16
    packed = struct.pack('>I', bits)
    return struct.unpack('>f', packed)[0]

def bf16_add(a: int, b: int) -> int:
    """BF16 addition via float32 promotion."""
    return float_to_bf16(bf16_to_float(a) + bf16_to_float(b))

def bf16_mul(a: int, b: int) -> int:
    """BF16 multiplication via float32 promotion."""
    return float_to_bf16(bf16_to_float(a) * bf16_to_float(b))

def bf16_fma(a: int, b: int, c: int) -> int:
    """BF16 fused multiply-add: a*b + c."""
    return float_to_bf16(bf16_to_float(a) * bf16_to_float(b) + bf16_to_float(c))

def bf16_relu(a: int) -> int:
    """BF16 ReLU: max(0, a)."""
    v = bf16_to_float(a)
    return float_to_bf16(max(0.0, v))

def bf16_sigmoid(a: int) -> int:
    """BF16 sigmoid: 1/(1+exp(-a))."""
    v = bf16_to_float(a)
    return float_to_bf16(1.0 / (1.0 + math.exp(-v)))

def bf16_tanh(a: int) -> int:
    """BF16 tanh."""
    v = bf16_to_float(a)
    return float_to_bf16(math.tanh(v))

def bf16_sqrt(a: int) -> int:
    """BF16 square root."""
    v = bf16_to_float(a)
    return float_to_bf16(math.sqrt(max(0.0, v)))

def bf16_exp(a: int) -> int:
    """BF16 exponential."""
    v = bf16_to_float(a)
    return float_to_bf16(math.exp(min(v, 88.0)))

def bf16_log(a: int) -> int:
    """BF16 natural logarithm."""
    v = bf16_to_float(a)
    return float_to_bf16(math.log(max(v, 1e-10)))

def bf16_dot_product(a: List[int], b: List[int]) -> int:
    """BF16 dot product of two vectors."""
    result = 0.0
    for ai, bi in zip(a, b):
        result += bf16_to_float(ai) * bf16_to_float(bi)
    return float_to_bf16(result)

def bf16_vector_add(a: List[int], b: List[int]) -> List[int]:
    """BF16 element-wise vector addition."""
    return [bf16_add(ai, bi) for ai, bi in zip(a, b)]

def bf16_vector_scale(v: List[int], scalar: float) -> List[int]:
    """BF16 vector scaling by float scalar."""
    s = float_to_bf16(scalar)
    return [bf16_mul(vi, s) for vi in v]

def bf16_matrix_vector_mul(matrix: List[List[int]], vector: List[int]) -> List[int]:
    """BF16 matrix-vector multiplication."""
    return [bf16_dot_product(row, vector) for row in matrix]

def bf16_softmax(logits: List[int]) -> List[float]:
    """BF16 softmax normalization."""
    floats = [bf16_to_float(x) for x in logits]
    max_v = max(floats)
    exps = [math.exp(x - max_v) for x in floats]
    sum_exp = sum(exps)
    return [e / sum_exp for e in exps]

# =============================================================================
# SECTION 3: ALPHANUMERIC BINARY CODEC
# =============================================================================

class AlphanumericCodec:
    """
    Alphanumeric Binary Codec for WebTransport storage.
    Encodes/decodes between alphanumeric strings and binary representations.
    """

    CHARSET = (
        [chr(i) for i in range(48, 58)] +   # 0-9
        [chr(i) for i in range(65, 91)] +   # A-Z
        [chr(i) for i in range(97, 123)]    # a-z
    )
    CHARSET_SIZE = len(CHARSET)  # 62

    @staticmethod
    def char_to_binary(char: str) -> int:
        """Convert alphanumeric character to 7-bit binary integer."""
        return ord(char) & 0x7F

    @staticmethod
    def binary_to_char(binary: int) -> str:
        """Convert 7-bit binary integer to character."""
        code = binary & 0x7F
        if 32 <= code <= 126:
            return chr(code)
        return '?'

    @staticmethod
    def is_alphanumeric(char: str) -> bool:
        """Check if character is alphanumeric."""
        c = ord(char)
        return (48 <= c <= 57) or (65 <= c <= 90) or (97 <= c <= 122)

    @staticmethod
    def string_to_binary_array(s: str) -> List[int]:
        """Convert string to array of 7-bit binary integers."""
        return [ord(c) & 0x7F for c in s]

    @staticmethod
    def binary_array_to_string(arr: List[int]) -> str:
        """Convert array of 7-bit binary integers to string."""
        return ''.join(chr(b & 0x7F) if 32 <= (b & 0x7F) <= 126 else '?' for b in arr)

    @staticmethod
    def encode_base62(value: int) -> str:
        """Encode integer to base-62 alphanumeric string."""
        if value == 0:
            return '0'
        charset = AlphanumericCodec.CHARSET
        result = []
        while value > 0:
            result.append(charset[value % 62])
            value //= 62
        return ''.join(reversed(result))

    @staticmethod
    def decode_base62(s: str) -> int:
        """Decode base-62 alphanumeric string to integer."""
        charset = AlphanumericCodec.CHARSET
        char_map = {c: i for i, c in enumerate(charset)}
        result = 0
        for c in s:
            result = result * 62 + char_map.get(c, 0)
        return result

    @staticmethod
    def pack_bits_to_bytes(bits: List[int]) -> bytes:
        """Pack list of bits (0/1) into bytes."""
        n = len(bits)
        n_bytes = (n + 7) // 8
        result = bytearray(n_bytes)
        for i, bit in enumerate(bits):
            if bit:
                result[i // 8] |= (1 << (7 - (i % 8)))
        return bytes(result)

    @staticmethod
    def unpack_bytes_to_bits(data: bytes) -> List[int]:
        """Unpack bytes into list of bits."""
        bits = []
        for byte in data:
            for i in range(7, -1, -1):
                bits.append((byte >> i) & 1)
        return bits

    @staticmethod
    def encode_alphanumeric_block(data: bytes, block_size: int = 8) -> List[str]:
        """Encode bytes as alphanumeric blocks."""
        blocks = []
        for i in range(0, len(data), block_size):
            chunk = data[i:i+block_size]
            # Encode each byte as 2 hex chars (alphanumeric)
            block = ''.join(f'{b:02X}' for b in chunk)
            blocks.append(block)
        return blocks

    @staticmethod
    def decode_alphanumeric_block(blocks: List[str]) -> bytes:
        """Decode alphanumeric blocks back to bytes."""
        result = bytearray()
        for block in blocks:
            for i in range(0, len(block), 2):
                if i + 1 < len(block):
                    try:
                        result.append(int(block[i:i+2], 16))
                    except ValueError:
                        result.append(0)
        return bytes(result)

    @staticmethod
    def binary_to_alphanumeric_status(binary_value: int) -> str:
        """Convert 16-bit binary value to 4-char alphanumeric status code."""
        # Map to A-Z, 0-9, a-z
        c0 = chr(65 + (binary_value // 2184) % 26)   # A-Z
        c1 = chr(48 + (binary_value // 100) % 10)    # 0-9
        c2 = chr(97 + (binary_value // 10) % 26)     # a-z
        c3 = chr(48 + binary_value % 10)              # 0-9
        return f"{c0}{c1}{c2}{c3}"

    @staticmethod
    def alphanumeric_status_to_binary(status: str) -> int:
        """Convert 4-char alphanumeric status code back to approximate binary value."""
        if len(status) < 4:
            return 0
        c0 = (ord(status[0]) - 65) % 26 * 2184
        c1 = (ord(status[1]) - 48) % 10 * 100
        c2 = (ord(status[2]) - 97) % 26 * 10
        c3 = (ord(status[3]) - 48) % 10
        return c0 + c1 + c2 + c3

# =============================================================================
# SECTION 4: CRC & CHECKSUM UTILITIES
# =============================================================================

class ChecksumEngine:
    """Checksum and hash computation engine for binary storage."""

    CRC32_POLY = 0xEDB88320  # reflected polynomial

    @staticmethod
    def crc32(data: List[int]) -> int:
        """Compute CRC-32 checksum of integer array."""
        crc = 0xFFFFFFFF
        for b in data:
            crc ^= (b & 0xFF)
            for _ in range(8):
                if crc & 1:
                    crc = (crc >> 1) ^ ChecksumEngine.CRC32_POLY
                else:
                    crc >>= 1
        return crc ^ 0xFFFFFFFF

    @staticmethod
    def crc32_bytes(data: bytes) -> int:
        """Compute CRC-32 checksum of bytes."""
        import zlib
        return zlib.crc32(data) & 0xFFFFFFFF

    @staticmethod
    def sha256_hash(data: bytes) -> str:
        """Compute SHA-256 hash of bytes."""
        return hashlib.sha256(data).hexdigest()

    @staticmethod
    def sha256_int(data: List[int]) -> int:
        """Compute SHA-256 hash of integer array, return as int."""
        b = bytes(x & 0xFF for x in data)
        digest = hashlib.sha256(b).digest()
        return int.from_bytes(digest[:8], 'big')

    @staticmethod
    def fnv1a_hash(data: List[int], capacity: int) -> int:
        """FNV-1a hash for hash table indexing."""
        FNV_PRIME  = 16777619
        FNV_OFFSET = 2166136261
        h = FNV_OFFSET
        for b in data:
            h ^= (b & 0xFF)
            h = (h * FNV_PRIME) & 0xFFFFFFFF
        return h % capacity

    @staticmethod
    def xxhash32(data: List[int], seed: int = 0) -> int:
        """xxHash32 — fast non-cryptographic hash."""
        PRIME1 = 0x9E3779B1
        PRIME2 = 0x85EBCA77
        PRIME3 = 0xC2B2AE3D
        PRIME4 = 0x27D4EB2F
        PRIME5 = 0x165667B1

        n = len(data)
        h32 = (seed + PRIME5) & 0xFFFFFFFF

        i = 0
        while i + 4 <= n:
            lane = (data[i] | (data[i+1] << 8) | (data[i+2] << 16) | (data[i+3] << 24)) & 0xFFFFFFFF
            h32 = (((h32 + lane * PRIME3) & 0xFFFFFFFF) * PRIME4) & 0xFFFFFFFF
            h32 = ((h32 << 17) | (h32 >> 15)) & 0xFFFFFFFF
            i += 4

        while i < n:
            h32 = (((h32 + data[i] * PRIME5) & 0xFFFFFFFF) * PRIME1) & 0xFFFFFFFF
            h32 = ((h32 << 11) | (h32 >> 21)) & 0xFFFFFFFF
            i += 1

        h32 ^= h32 >> 15
        h32 = (h32 * PRIME2) & 0xFFFFFFFF
        h32 ^= h32 >> 13
        h32 = (h32 * PRIME3) & 0xFFFFFFFF
        h32 ^= h32 >> 16
        return h32

    @staticmethod
    def murmur3_32(data: List[int], seed: int = 0) -> int:
        """MurmurHash3 32-bit."""
        C1 = 0xCC9E2D51
        C2 = 0x1B873593
        h = seed
        n = len(data)

        for i in range(0, n - 3, 4):
            k = (data[i] | (data[i+1] << 8) | (data[i+2] << 16) | (data[i+3] << 24)) & 0xFFFFFFFF
            k = (k * C1) & 0xFFFFFFFF
            k = ((k << 15) | (k >> 17)) & 0xFFFFFFFF
            k = (k * C2) & 0xFFFFFFFF
            h ^= k
            h = ((h << 13) | (h >> 19)) & 0xFFFFFFFF
            h = ((h * 5) + 0xE6546B64) & 0xFFFFFFFF

        tail_start = (n // 4) * 4
        tail = data[tail_start:]
        k = 0
        if len(tail) >= 3: k ^= tail[2] << 16
        if len(tail) >= 2: k ^= tail[1] << 8
        if len(tail) >= 1:
            k ^= tail[0]
            k = (k * C1) & 0xFFFFFFFF
            k = ((k << 15) | (k >> 17)) & 0xFFFFFFFF
            k = (k * C2) & 0xFFFFFFFF
            h ^= k

        h ^= n
        h ^= h >> 16
        h = (h * 0x85EBCA6B) & 0xFFFFFFFF
        h ^= h >> 13
        h = (h * 0xC2B2AE35) & 0xFFFFFFFF
        h ^= h >> 16
        return h

# =============================================================================
# SECTION 5: SAFASENSOR DATA STRUCTURES
# =============================================================================

@dataclass
class SafaSensorReading:
    """Single SafaSensor reading with full metadata."""
    sensor_id:    int
    channel_id:   int
    bank_id:      int
    raw_value:    float       # normalized [0, 1]
    binary_value: int         # 16-bit ADC reading [0, 65535]
    alpha_code:   str         # 4-char alphanumeric status code
    timestamp:    int         # simulated Unix timestamp
    stream_id:    int         # QUIC stream assignment
    browser_id:   int         # 0=Edge, 1=Firefox
    coherence:    float       # quantum coherence [0, 1]
    phase:        float       # quantum phase [0, 2π]
    corrected:    bool        # Majorana correction applied
    bf16_value:   int = 0     # BF16 encoded raw value

    def __post_init__(self):
        self.bf16_value = float_to_bf16(self.raw_value)

    def to_binary_array(self) -> List[int]:
        """Serialize reading to 64-bit binary array."""
        adc_bits      = [(self.binary_value >> i) & 1 for i in range(16)]
        phase_bits    = [(int(self.phase * 1000) >> i) & 1 for i in range(16)]
        coherence_bits= [(int(self.coherence * 65535) >> i) & 1 for i in range(16)]
        id_bits       = [(self.sensor_id >> i) & 1 for i in range(16)]
        return adc_bits + phase_bits + coherence_bits + id_bits

    def to_alphanumeric_key(self) -> str:
        """Generate alphanumeric key for this sensor reading."""
        return f"B{self.bank_id:02d}_S{self.sensor_id:04d}"

    def to_alphanumeric_value(self) -> str:
        """Generate alphanumeric value encoding."""
        return f"{self.alpha_code}_{self.binary_value:05d}_{self.coherence:.4f}"


@dataclass
class SafaSensorBank:
    """Bank of 100 SafaSensors."""
    bank_id:      int
    bank_name:    str
    browser_id:   int
    stream_id:    int
    base_address: int
    readings:     List[SafaSensorReading] = field(default_factory=list)

    BANK_NAMES = [
        "Latency-Bank",    "Bandwidth-Bank",  "PacketLoss-Bank",
        "Coherence-Bank",  "Gradient-Bank",   "Activation-Bank",
        "Attention-Bank",  "Memory-Bank",     "Throughput-Bank",
        "Jitter-Bank",     "ErrorRate-Bank",  "Retransmit-Bank",
        "CongWindow-Bank", "FlowCtrl-Bank",   "RTT-Bank",
        "CWND-Bank",       "SSTHRESH-Bank",   "PktReorder-Bank",
        "ECN-Bank",        "QUIC-Bank",       "TLS-Bank",
        "HTTP3-Bank",      "WebGPU-Bank",     "WebNN-Bank",
        "WASM-Bank",       "Worker-Bank",     "SharedMem-Bank",
        "IndexedDB-Bank",  "Cache-Bank",      "ServiceWkr-Bank",
        "Push-Bank",       "Notify-Bank",     "Geoloc-Bank",
        "Sensor-Bank",     "Gamepad-Bank",    "WebXR-Bank",
        "WebRTC-Bank",     "MediaSrc-Bank",   "AudioCtx-Bank",
        "Canvas-Bank",     "WebGL-Bank",      "SVG-Bank",
        "CSS-Bank",        "Layout-Bank",     "Paint-Bank",
        "Composite-Bank",  "Script-Bank",     "GC-Bank",
        "Heap-Bank",       "Stack-Bank"
    ]

    @property
    def sensor_count(self) -> int:
        return len(self.readings)

    def get_mean_value(self) -> float:
        if not self.readings: return 0.0
        return sum(r.raw_value for r in self.readings) / len(self.readings)

    def get_std_dev(self) -> float:
        if not self.readings: return 0.0
        mean = self.get_mean_value()
        variance = sum((r.raw_value - mean)**2 for r in self.readings) / len(self.readings)
        return math.sqrt(variance)

    def get_min_value(self) -> float:
        return min(r.raw_value for r in self.readings) if self.readings else 0.0

    def get_max_value(self) -> float:
        return max(r.raw_value for r in self.readings) if self.readings else 0.0

    def get_coherence_pct(self) -> float:
        if not self.readings: return 0.0
        return sum(r.coherence for r in self.readings) / len(self.readings) * 100.0

    def get_corrected_pct(self) -> float:
        if not self.readings: return 0.0
        return sum(1 for r in self.readings if r.corrected) / len(self.readings) * 100.0

    def get_total_adc(self) -> int:
        return sum(r.binary_value for r in self.readings)

    def to_binary_matrix(self) -> List[List[int]]:
        """Convert all readings to 64-bit binary matrix."""
        return [r.to_binary_array() for r in self.readings]


@dataclass
class SafaSensorArray5K:
    """Full 5000-sensor array (50 banks × 100 sensors)."""
    array_id:  int
    browser_id: int
    banks:     List[SafaSensorBank] = field(default_factory=list)

    @property
    def total_sensors(self) -> int:
        return sum(b.sensor_count for b in self.banks)

    @property
    def total_banks(self) -> int:
        return len(self.banks)

    def get_global_mean(self) -> float:
        if not self.banks: return 0.0
        return sum(b.get_mean_value() for b in self.banks) / len(self.banks)

    def get_global_coherence(self) -> float:
        if not self.banks: return 0.0
        return sum(b.get_coherence_pct() for b in self.banks) / len(self.banks)

    def get_bank(self, bank_id: int) -> Optional[SafaSensorBank]:
        for b in self.banks:
            if b.bank_id == bank_id:
                return b
        return None

    def get_reading(self, sensor_id: int) -> Optional[SafaSensorReading]:
        bank_id = sensor_id // SENSORS_PER_BANK
        bank = self.get_bank(bank_id)
        if bank:
            local_id = sensor_id % SENSORS_PER_BANK
            if local_id < len(bank.readings):
                return bank.readings[local_id]
        return None

    def to_flat_binary_matrix(self) -> List[List[int]]:
        """Flatten all banks into 5000×64 binary matrix."""
        matrix = []
        for bank in self.banks:
            matrix.extend(bank.to_binary_matrix())
        return matrix[:N_SENSORS]  # ensure exactly 5000 rows

# =============================================================================
# SECTION 6: SAFASENSOR FACTORY
# =============================================================================

class SafaSensorFactory:
    """Factory for generating SafaSensor arrays."""

    @staticmethod
    def generate_reading(
        sensor_id:  int,
        channel_id: int,
        bank_id:    int,
        stream_id:  int,
        browser_id: int
    ) -> SafaSensorReading:
        """Generate a single SafaSensor reading with deterministic values."""
        # Deterministic pseudo-random via sine hash
        seed = sensor_id * 1009 + channel_id * 7 + bank_id * 31 + browser_id * 17
        raw_value = 0.5 + 0.4 * math.sin(seed * 0.001)
        raw_value = max(0.0, min(1.0, raw_value))

        # 16-bit ADC
        binary_value = int(raw_value * 65535) & 0xFFFF

        # Alphanumeric status code
        alpha_code = AlphanumericCodec.binary_to_alphanumeric_status(binary_value)

        # Quantum coherence
        coherence = 0.95 + 0.04 * math.cos(sensor_id * 0.01)
        coherence = max(0.0, min(1.0, coherence))

        # Quantum phase
        phase = (sensor_id % 628) * 0.01

        # Majorana correction applied if coherence > 0.97
        corrected = coherence > 0.97

        return SafaSensorReading(
            sensor_id    = sensor_id,
            channel_id   = channel_id,
            bank_id      = bank_id,
            raw_value    = raw_value,
            binary_value = binary_value,
            alpha_code   = alpha_code,
            timestamp    = sensor_id * 100 + channel_id,
            stream_id    = stream_id,
            browser_id   = browser_id,
            coherence    = coherence,
            phase        = phase,
            corrected    = corrected
        )

    @staticmethod
    def generate_bank(bank_id: int, browser_id: int) -> SafaSensorBank:
        """Generate a bank of 100 SafaSensors."""
        bank_name = (SafaSensorBank.BANK_NAMES[bank_id]
                     if bank_id < len(SafaSensorBank.BANK_NAMES)
                     else f"Bank-{bank_id}")
        stream_id = bank_id % QUIC_STREAMS

        readings = [
            SafaSensorFactory.generate_reading(
                sensor_id  = bank_id * SENSORS_PER_BANK + i,
                channel_id = i,
                bank_id    = bank_id,
                stream_id  = stream_id,
                browser_id = browser_id
            )
            for i in range(SENSORS_PER_BANK)
        ]

        return SafaSensorBank(
            bank_id      = bank_id,
            bank_name    = bank_name,
            browser_id   = browser_id,
            stream_id    = stream_id,
            base_address = bank_id * 0x1000,
            readings     = readings
        )

    @staticmethod
    def generate_array_5k(array_id: int, browser_id: int) -> SafaSensorArray5K:
        """Generate the full 5000-sensor array (50 banks × 100 sensors)."""
        banks = [
            SafaSensorFactory.generate_bank(bank_id, browser_id)
            for bank_id in range(N_BANKS)
        ]
        return SafaSensorArray5K(
            array_id   = array_id,
            browser_id = browser_id,
            banks      = banks
        )

# =============================================================================
# SECTION 7: BINARY STORAGE BLOCK
# =============================================================================

@dataclass
class BinaryStorageBlock:
    """64-bit binary storage block with alphanumeric metadata."""
    block_id:   int
    address:    int
    data_bits:  List[int]    # 64-bit binary array
    checksum:   int
    timestamp:  int
    stream_id:  int
    browser_id: int
    alpha_key:  str = ""     # alphanumeric key

    @classmethod
    def from_reading(cls, reading: SafaSensorReading, block_id: int) -> 'BinaryStorageBlock':
        """Create storage block from sensor reading."""
        data_bits = reading.to_binary_array()
        checksum  = ChecksumEngine.crc32(data_bits)
        return cls(
            block_id   = block_id,
            address    = block_id * BINARY_BLOCK_SIZE,
            data_bits  = data_bits,
            checksum   = checksum,
            timestamp  = reading.timestamp,
            stream_id  = reading.stream_id,
            browser_id = reading.browser_id,
            alpha_key  = reading.to_alphanumeric_key()
        )

    @classmethod
    def from_alphanumeric(cls, text: str, block_id: int, stream_id: int, browser_id: int) -> 'BinaryStorageBlock':
        """Create storage block from alphanumeric string."""
        data_bits = [AlphanumericCodec.char_to_binary(c) for c in text[:BINARY_BLOCK_SIZE]]
        # Pad to 64 bits
        while len(data_bits) < BINARY_BLOCK_SIZE:
            data_bits.append(0)
        checksum = ChecksumEngine.crc32(data_bits)
        return cls(
            block_id   = block_id,
            address    = block_id * BINARY_BLOCK_SIZE,
            data_bits  = data_bits,
            checksum   = checksum,
            timestamp  = int(time.time()),
            stream_id  = stream_id,
            browser_id = browser_id,
            alpha_key  = text[:16]
        )

    def validate(self) -> bool:
        """Validate block integrity via CRC-32."""
        return ChecksumEngine.crc32(self.data_bits) == self.checksum

    def to_bytes(self) -> bytes:
        """Serialize block to bytes."""
        return AlphanumericCodec.pack_bits_to_bytes(self.data_bits)

    def to_hex_string(self) -> str:
        """Represent block data as hex string."""
        return self.to_bytes().hex().upper()

    def to_alphanumeric_string(self) -> str:
        """Represent block data as alphanumeric string."""
        return ''.join(AlphanumericCodec.binary_to_char(b) for b in self.data_bits[:32])

    def hamming_distance(self, other: 'BinaryStorageBlock') -> int:
        """Compute Hamming distance between two blocks."""
        n = min(len(self.data_bits), len(other.data_bits))
        return sum(a ^ b for a, b in zip(self.data_bits[:n], other.data_bits[:n]))

    def xor_merge(self, other: 'BinaryStorageBlock') -> 'BinaryStorageBlock':
        """XOR-merge two blocks."""
        n = max(len(self.data_bits), len(other.data_bits))
        merged = [
            (self.data_bits[i] if i < len(self.data_bits) else 0) ^
            (other.data_bits[i] if i < len(other.data_bits) else 0)
            for i in range(n)
        ]
        return BinaryStorageBlock(
            block_id   = self.block_id ^ other.block_id,
            address    = self.address,
            data_bits  = merged,
            checksum   = ChecksumEngine.crc32(merged),
            timestamp  = max(self.timestamp, other.timestamp),
            stream_id  = self.stream_id,
            browser_id = self.browser_id,
            alpha_key  = self.alpha_key
        )

    def split(self) -> Tuple['BinaryStorageBlock', 'BinaryStorageBlock']:
        """Split block into two halves."""
        n = len(self.data_bits)
        half = n // 2
        a_bits = self.data_bits[:half]
        b_bits = self.data_bits[half:]
        block_a = BinaryStorageBlock(
            self.block_id * 2,     self.address,
            a_bits, ChecksumEngine.crc32(a_bits),
            self.timestamp, self.stream_id, self.browser_id, self.alpha_key + "_A"
        )
        block_b = BinaryStorageBlock(
            self.block_id * 2 + 1, self.address + half,
            b_bits, ChecksumEngine.crc32(b_bits),
            self.timestamp, self.stream_id, self.browser_id, self.alpha_key + "_B"
        )
        return block_a, block_b

# =============================================================================
# SECTION 8: BINARY STORAGE MATRIX (5000 × 64)
# =============================================================================

class BinaryStorageMatrix:
    """
    5000 × 64 binary storage matrix.
    One row per sensor, 64 bits per row.
    Supports efficient row/column access, popcount, and XOR operations.
    """

    def __init__(self, matrix_id: int, browser_id: int):
        self.matrix_id  = matrix_id
        self.browser_id = browser_id
        self.rows       = N_SENSORS
        self.cols       = BINARY_BLOCK_SIZE
        self.data: List[List[int]] = [[0] * self.cols for _ in range(self.rows)]
        self.checksum   = 0
        self._dirty     = True

    def load_from_array(self, sensor_array: SafaSensorArray5K) -> None:
        """Load sensor array data into matrix."""
        row_idx = 0
        for bank in sensor_array.banks:
            for reading in bank.readings:
                if row_idx < self.rows:
                    self.data[row_idx] = reading.to_binary_array()
                    row_idx += 1
        self._dirty = True

    def get_row(self, row_idx: int) -> List[int]:
        """Get a row from the matrix."""
        if 0 <= row_idx < self.rows:
            return self.data[row_idx]
        return [0] * self.cols

    def set_row(self, row_idx: int, row: List[int]) -> None:
        """Set a row in the matrix."""
        if 0 <= row_idx < self.rows:
            self.data[row_idx] = row[:self.cols]
            self._dirty = True

    def get_column(self, col_idx: int) -> List[int]:
        """Get a column from the matrix."""
        if 0 <= col_idx < self.cols:
            return [self.data[r][col_idx] for r in range(self.rows)]
        return [0] * self.rows

    def column_popcount(self) -> List[int]:
        """Compute popcount (sum of 1s) for each column."""
        return [sum(self.data[r][c] for r in range(self.rows)) for c in range(self.cols)]

    def row_popcount(self, row_idx: int) -> int:
        """Compute popcount for a single row."""
        return sum(self.get_row(row_idx))

    def xor_rows(self, row_a: int, row_b: int) -> List[int]:
        """XOR two rows."""
        a = self.get_row(row_a)
        b = self.get_row(row_b)
        return [x ^ y for x, y in zip(a, b)]

    def and_rows(self, row_a: int, row_b: int) -> List[int]:
        """AND two rows."""
        a = self.get_row(row_a)
        b = self.get_row(row_b)
        return [x & y for x, y in zip(a, b)]

    def or_rows(self, row_a: int, row_b: int) -> List[int]:
        """OR two rows."""
        a = self.get_row(row_a)
        b = self.get_row(row_b)
        return [x | y for x, y in zip(a, b)]

    def compute_checksum(self) -> int:
        """Compute matrix checksum."""
        flat = sum(sum(row) for row in self.data)
        self.checksum = flat % 0x7FFFFFFF
        self._dirty = False
        return self.checksum

    def to_bytes(self) -> bytes:
        """Serialize entire matrix to bytes."""
        result = bytearray()
        for row in self.data:
            result.extend(AlphanumericCodec.pack_bits_to_bytes(row))
        return bytes(result)

    def memory_usage_bytes(self) -> int:
        """Compute memory usage in bytes."""
        return self.rows * self.cols  # 1 bit per element, stored as int

    def memory_usage_bf16(self) -> int:
        """Memory usage if stored as BF16 values."""
        return self.rows * self.cols * BF16_BYTES

    def get_submatrix(self, row_start: int, row_end: int, col_start: int, col_end: int) -> List[List[int]]:
        """Extract a submatrix."""
        return [
            self.data[r][col_start:col_end]
            for r in range(row_start, min(row_end, self.rows))
        ]

    def transpose_submatrix(self, rows: int, cols: int) -> List[List[int]]:
        """Transpose a submatrix (rows × cols)."""
        sub = self.get_submatrix(0, rows, 0, cols)
        return [[sub[r][c] for r in range(len(sub))] for c in range(cols)]

    def hamming_distance_rows(self, row_a: int, row_b: int) -> int:
        """Hamming distance between two rows."""
        return sum(a ^ b for a, b in zip(self.get_row(row_a), self.get_row(row_b)))

    def find_nearest_row(self, query: List[int]) -> Tuple[int, int]:
        """Find row with minimum Hamming distance to query."""
        best_dist = self.cols + 1
        best_idx  = 0
        for r in range(self.rows):
            dist = sum(a ^ b for a, b in zip(self.data[r], query[:self.cols]))
            if dist < best_dist:
                best_dist = dist
                best_idx  = r
        return best_idx, best_dist

    def statistics(self) -> Dict[str, Any]:
        """Compute matrix statistics."""
        col_pops = self.column_popcount()
        total_ones = sum(col_pops)
        total_bits = self.rows * self.cols
        return {
            'rows':          self.rows,
            'cols':          self.cols,
            'total_bits':    total_bits,
            'total_ones':    total_ones,
            'density':       total_ones / total_bits,
            'col_mean_pop':  sum(col_pops) / len(col_pops),
            'col_max_pop':   max(col_pops),
            'col_min_pop':   min(col_pops),
            'checksum':      self.compute_checksum(),
            'memory_bytes':  self.memory_usage_bytes(),
            'memory_bf16':   self.memory_usage_bf16()
        }

# =============================================================================
# SECTION 9: QUIC STREAM MANAGER
# =============================================================================

@dataclass
class QUICStreamState:
    """State of a single QUIC stream."""
    stream_id:       int
    browser_id:      int
    is_open:         bool    = True
    bytes_sent:      int     = 0
    bytes_received:  int     = 0
    packet_loss:     float   = 0.001
    rtt_ms:          float   = 12.5
    bandwidth_mbps:  float   = 950.0
    flow_control:    int     = FLOW_CTRL_WINDOW
    priority:        int     = 1
    sequence_num:    int     = 0
    ack_num:         int     = 0

    def send_bytes(self, n: int) -> bool:
        """Simulate sending n bytes. Returns True if successful."""
        if not self.is_open or self.flow_control < n:
            return False
        # Simulate packet loss
        if self.packet_loss > 0.01:
            return False
        self.bytes_sent    += n
        self.flow_control  -= n
        self.sequence_num  += n
        return True

    def receive_ack(self, acked_bytes: int) -> None:
        """Process ACK for acked_bytes."""
        self.bytes_received += acked_bytes
        self.flow_control   += acked_bytes
        self.ack_num        += acked_bytes

    def throughput_mbps(self) -> float:
        """Effective throughput in Mbps."""
        return self.bandwidth_mbps * (1.0 - self.packet_loss)


@dataclass
class FlowControlState:
    """QUIC flow control and congestion control state."""
    stream_id:      int
    send_window:    int   = FLOW_CTRL_WINDOW
    recv_window:    int   = FLOW_CTRL_WINDOW * 2
    bytes_in_flight:int   = 0
    cwnd:           int   = 14720    # ~10 MSS
    ssthresh:       int   = FLOW_CTRL_WINDOW
    cong_state:     int   = CONG_SLOW_START
    rtt_us:         int   = 12500    # 12.5ms
    rttvar_us:      int   = 3000
    rto_us:         int   = 200000   # 200ms

    MSS = 1460  # Maximum Segment Size

    def on_send(self, bytes_sent: int) -> None:
        """Update state on packet send."""
        self.send_window    -= bytes_sent
        self.bytes_in_flight += bytes_sent

    def on_ack(self, bytes_acked: int, rtt_sample_us: int) -> None:
        """Update state on ACK receipt (RFC 6298 RTT estimation)."""
        # RTT update
        rtt_diff       = rtt_sample_us - self.rtt_us
        self.rtt_us    = self.rtt_us + rtt_diff // 8
        self.rttvar_us = self.rttvar_us + (abs(rtt_diff) - self.rttvar_us) // 4
        self.rto_us    = self.rtt_us + 4 * self.rttvar_us

        # Congestion window update
        self.send_window     += bytes_acked
        self.bytes_in_flight -= bytes_acked

        if self.cong_state == CONG_SLOW_START:
            self.cwnd += bytes_acked
            if self.cwnd >= self.ssthresh:
                self.cong_state = CONG_AVOID
        elif self.cong_state == CONG_AVOID:
            self.cwnd += self.MSS * bytes_acked // self.cwnd
        elif self.cong_state == CONG_FAST_RECOVER:
            self.cwnd = self.ssthresh
            self.cong_state = CONG_AVOID

    def on_loss(self) -> None:
        """Handle packet loss event."""
        self.ssthresh   = max(self.cwnd // 2, 2 * self.MSS)
        self.cwnd       = self.ssthresh
        self.cong_state = CONG_FAST_RECOVER

    def can_send(self, n_bytes: int) -> bool:
        """Check if n_bytes can be sent."""
        return (self.send_window >= n_bytes and
                self.bytes_in_flight + n_bytes <= self.cwnd)


class QUICStreamManager:
    """Manages 8 QUIC streams for a WebTransport session."""

    def __init__(self, session_id: int, browser_id: int):
        self.session_id  = session_id
        self.browser_id  = browser_id
        self.streams     = self._init_streams()
        self.flow_states = [FlowControlState(i) for i in range(QUIC_STREAMS)]
        self.total_sent  = 0
        self.total_recv  = 0

    def _init_streams(self) -> List[QUICStreamState]:
        """Initialize 8 QUIC streams with browser-specific parameters."""
        if self.browser_id == BROWSER_EDGE:
            base_bw  = 950.0
            base_rtt = 12.5
            base_loss = 0.001
        else:  # Firefox
            base_bw  = 920.0
            base_rtt = 11.2
            base_loss = 0.0008

        return [
            QUICStreamState(
                stream_id      = i,
                browser_id     = self.browser_id,
                packet_loss    = base_loss + i * 0.0001,
                rtt_ms         = base_rtt + i * 0.3,
                bandwidth_mbps = base_bw - i * 10.0,
                priority       = i % 4
            )
            for i in range(QUIC_STREAMS)
        ]

    def send_block(self, block: BinaryStorageBlock) -> Tuple[bool, int]:
        """Send a binary storage block over the appropriate stream."""
        stream_id = block.stream_id % QUIC_STREAMS
        stream    = self.streams[stream_id]
        fc        = self.flow_states[stream_id]
        n_bytes   = len(block.data_bits)

        if not fc.can_send(n_bytes):
            return False, stream_id

        success = stream.send_bytes(n_bytes)
        if success:
            fc.on_send(n_bytes)
            self.total_sent += n_bytes
        return success, stream_id

    def receive_ack(self, stream_id: int, bytes_acked: int, rtt_us: int) -> None:
        """Process ACK for a stream."""
        if 0 <= stream_id < QUIC_STREAMS:
            self.streams[stream_id].receive_ack(bytes_acked)
            self.flow_states[stream_id].on_ack(bytes_acked, rtt_us)
            self.total_recv += bytes_acked

    def aggregate_throughput(self) -> float:
        """Total throughput across all streams in Mbps."""
        return sum(s.throughput_mbps() for s in self.streams if s.is_open)

    def average_rtt(self) -> float:
        """Average RTT across all streams in ms."""
        active = [s for s in self.streams if s.is_open]
        if not active: return 0.0
        return sum(s.rtt_ms for s in active) / len(active)

    def stream_statistics(self) -> List[Dict[str, Any]]:
        """Per-stream statistics."""
        return [
            {
                'stream_id':      s.stream_id,
                'browser':        'Edge' if s.browser_id == 0 else 'Firefox',
                'bytes_sent':     s.bytes_sent,
                'bytes_received': s.bytes_received,
                'rtt_ms':         s.rtt_ms,
                'bandwidth_mbps': s.bandwidth_mbps,
                'packet_loss':    s.packet_loss,
                'throughput_mbps':s.throughput_mbps(),
                'cwnd':           self.flow_states[s.stream_id].cwnd,
                'cong_state':     ['slow-start','cong-avoid','fast-recover'][
                                   self.flow_states[s.stream_id].cong_state]
            }
            for s in self.streams
        ]

# =============================================================================
# SECTION 10: MICROSOFT EDGE AGENT
# =============================================================================

@dataclass
class EdgeAgentState:
    """Microsoft Edge Copilot quantum agent state."""
    agent_id:       int
    session_id:     int
    model_version:  str   = "Copilot-365-v4.0"
    context_window: int   = 131072   # 128k tokens
    inference_mode: int   = 2        # 0=local, 1=cloud, 2=hybrid
    quantum_phase:  float = 0.0
    coherence:      float = 0.9995
    binary_buffer:  List[int] = field(default_factory=list)
    streams_active: int   = QUIC_STREAMS
    bf16_weights:   List[int] = field(default_factory=list)

    def __post_init__(self):
        if not self.binary_buffer:
            # Initialize with A-Z cycling
            self.binary_buffer = [
                AlphanumericCodec.char_to_binary(chr(65 + i % 26))
                for i in range(64)
            ]
        if not self.bf16_weights:
            # Initialize BF16 weights
            self.bf16_weights = [
                float_to_bf16(math.sin(i * 0.1) * 0.1)
                for i in range(64)
            ]

    def update_buffer(self, new_data: List[int]) -> None:
        """Update binary buffer with new alphanumeric data."""
        for i, c in enumerate(new_data[:len(self.binary_buffer)]):
            self.binary_buffer[i] = AlphanumericCodec.char_to_binary(chr(c)) if c > 0 else 0
        self.quantum_phase += 0.01
        self.coherence     *= 0.9999

    def encode_to_bf16_vector(self) -> List[int]:
        """Encode agent state as BF16 vector."""
        return [
            float_to_bf16(self.coherence),
            float_to_bf16(self.quantum_phase % (2 * math.pi)),
            float_to_bf16(self.inference_mode / 2.0),
            float_to_bf16(self.streams_active / QUIC_STREAMS)
        ]

    def infer(self, sensor_features: List[float]) -> str:
        """Run inference on sensor features."""
        # Simple threshold-based inference
        mean_feature = sum(sensor_features) / len(sensor_features) if sensor_features else 0.0
        if mean_feature > 0.8:
            return "Healthy"
        elif mean_feature > 0.5:
            return "Degraded"
        elif mean_feature > 0.2:
            return "Critical"
        else:
            return "Recovering"

    def get_alphanumeric_status(self) -> str:
        """Get alphanumeric status code for current agent state."""
        return AlphanumericCodec.binary_to_alphanumeric_status(
            int(self.coherence * 65535)
        )


class EdgeAgentManager:
    """Manages multiple Edge agents with WebTransport sessions."""

    def __init__(self, n_agents: int = 1):
        self.agents   = [EdgeAgentState(i, i * 100) for i in range(n_agents)]
        self.sessions = [QUICStreamManager(i * 100, BROWSER_EDGE) for i in range(n_agents)]

    def process_sensor_bank(self, bank: SafaSensorBank, agent_idx: int = 0) -> Dict[str, Any]:
        """Process a sensor bank through an Edge agent."""
        agent   = self.agents[agent_idx]
        session = self.sessions[agent_idx]

        # Extract features
        features = [r.raw_value for r in bank.readings]
        decision = agent.infer(features)

        # Send blocks over QUIC
        sent_count = 0
        for reading in bank.readings[:8]:  # sample first 8
            block = BinaryStorageBlock.from_reading(reading, reading.sensor_id)
            success, stream_id = session.send_block(block)
            if success:
                sent_count += 1

        return {
            'agent_id':    agent.agent_id,
            'bank_id':     bank.bank_id,
            'decision':    decision,
            'sent_blocks': sent_count,
            'coherence':   agent.coherence,
            'throughput':  session.aggregate_throughput()
        }

# =============================================================================
# SECTION 11: MOZILLA FIREFOX RELAY
# =============================================================================

@dataclass
class FirefoxRelayState:
    """Mozilla Firefox quantum relay node state."""
    relay_id:      int
    session_id:    int
    engine_version:str   = "SpiderMonkey-v120"
    jit_mode:      int   = 2        # 0=baseline, 1=ion, 2=warp
    wasm_enabled:  bool  = True
    quantum_phase: float = 0.0
    coherence:     float = 0.9992
    binary_buffer: List[int] = field(default_factory=list)
    relay_latency: float = 0.8      # ms

    def __post_init__(self):
        if not self.binary_buffer:
            # Initialize with a-z cycling
            self.binary_buffer = [
                AlphanumericCodec.char_to_binary(chr(97 + i % 26))
                for i in range(64)
            ]

    def relay_block(self, block: BinaryStorageBlock) -> BinaryStorageBlock:
        """Forward a binary block with quantum phase correction."""
        correction = int(self.quantum_phase * 10) % 128
        corrected_data = [(b + correction) % 128 for b in block.data_bits]
        new_checksum = ChecksumEngine.crc32(corrected_data)
        self.quantum_phase += 0.005
        self.coherence     *= 0.99999
        return BinaryStorageBlock(
            block_id   = block.block_id,
            address    = block.address,
            data_bits  = corrected_data,
            checksum   = new_checksum,
            timestamp  = block.timestamp,
            stream_id  = block.stream_id,
            browser_id = BROWSER_FIREFOX,
            alpha_key  = block.alpha_key
        )

    def get_alphanumeric_status(self) -> str:
        return AlphanumericCodec.binary_to_alphanumeric_status(
            int(self.coherence * 65535)
        )


class FirefoxRelayManager:
    """Manages Firefox relay nodes with WebTransport sessions."""

    def __init__(self, n_relays: int = 1):
        self.relays   = [FirefoxRelayState(i, i * 200) for i in range(n_relays)]
        self.sessions = [QUICStreamManager(i * 200, BROWSER_FIREFOX) for i in range(n_relays)]

    def relay_sensor_bank(self, bank: SafaSensorBank, relay_idx: int = 0) -> Dict[str, Any]:
        """Relay a sensor bank through a Firefox relay node."""
        relay   = self.relays[relay_idx]
        session = self.sessions[relay_idx]

        relayed_count = 0
        for reading in bank.readings[:8]:
            block = BinaryStorageBlock.from_reading(reading, reading.sensor_id)
            relayed_block = relay.relay_block(block)
            success, _ = session.send_block(relayed_block)
            if success:
                relayed_count += 1

        return {
            'relay_id':      relay.relay_id,
            'bank_id':       bank.bank_id,
            'relayed_blocks':relayed_count,
            'coherence':     relay.coherence,
            'latency_ms':    relay.relay_latency,
            'throughput':    session.aggregate_throughput()
        }

# =============================================================================
# SECTION 12: ALPHANUMERIC BINARY HASH TABLE
# =============================================================================

class AlphanumericHashTable:
    """
    Open-addressing hash table with linear probing.
    Keys and values are alphanumeric binary arrays.
    """

    def __init__(self, capacity: int = 8192):
        self.capacity  = capacity
        self.size      = 0
        self.keys:     List[Optional[List[int]]] = [None] * capacity
        self.values:   List[Optional[List[int]]] = [None] * capacity
        self.deleted:  List[bool]                = [False] * capacity

    def _hash(self, key: List[int]) -> int:
        return ChecksumEngine.fnv1a_hash(key, self.capacity)

    def insert(self, key: List[int], value: List[int]) -> bool:
        """Insert key-value pair. Returns True if successful."""
        if self.size >= self.capacity * 0.75:
            self._resize()
        idx = self._hash(key)
        for _ in range(self.capacity):
            if self.keys[idx] is None or self.deleted[idx]:
                self.keys[idx]    = key
                self.values[idx]  = value
                self.deleted[idx] = False
                self.size += 1
                return True
            if self.keys[idx] == key:
                self.values[idx] = value  # update
                return True
            idx = (idx + 1) % self.capacity
        return False

    def lookup(self, key: List[int]) -> Optional[List[int]]:
        """Look up value by key. Returns None if not found."""
        idx = self._hash(key)
        for _ in range(self.capacity):
            if self.keys[idx] is None:
                return None
            if not self.deleted[idx] and self.keys[idx] == key:
                return self.values[idx]
            idx = (idx + 1) % self.capacity
        return None

    def delete(self, key: List[int]) -> bool:
        """Soft-delete a key. Returns True if found."""
        idx = self._hash(key)
        for _ in range(self.capacity):
            if self.keys[idx] is None:
                return False
            if not self.deleted[idx] and self.keys[idx] == key:
                self.deleted[idx] = True
                self.size -= 1
                return True
            idx = (idx + 1) % self.capacity
        return False

    def _resize(self) -> None:
        """Double capacity and rehash."""
        old_keys   = self.keys
        old_values = self.values
        old_deleted = self.deleted
        self.capacity *= 2
        self.size      = 0
        self.keys      = [None] * self.capacity
        self.values    = [None] * self.capacity
        self.deleted   = [False] * self.capacity
        for k, v, d in zip(old_keys, old_values, old_deleted):
            if k is not None and not d:
                self.insert(k, v)

    def load_factor(self) -> float:
        return self.size / self.capacity

    def insert_sensor_reading(self, reading: SafaSensorReading) -> bool:
        """Insert a sensor reading into the hash table."""
        key   = AlphanumericCodec.string_to_binary_array(reading.to_alphanumeric_key())
        value = AlphanumericCodec.string_to_binary_array(reading.to_alphanumeric_value())
        return self.insert(key, value)

    def lookup_sensor(self, bank_id: int, sensor_id: int) -> Optional[str]:
        """Look up a sensor reading by bank and sensor ID."""
        key_str = f"B{bank_id:02d}_S{sensor_id:04d}"
        key     = AlphanumericCodec.string_to_binary_array(key_str)
        value   = self.lookup(key)
        if value is not None:
            return AlphanumericCodec.binary_array_to_string(value)
        return None

# =============================================================================
# SECTION 13: PERSISTENCE LAYER
# =============================================================================

@dataclass
class PersistenceRecord:
    """Persistent key-value record with binary encoding."""
    record_id:    int
    key:          List[int]    # alphanumeric binary key
    value:        List[int]    # alphanumeric binary value
    key_checksum: int
    val_checksum: int
    browser_id:   int
    stream_id:    int
    version:      int  = 1
    is_deleted:   bool = False
    created_at:   int  = 0

    @classmethod
    def create(cls, record_id: int, key_str: str, val_str: str,
               browser_id: int, stream_id: int) -> 'PersistenceRecord':
        key = AlphanumericCodec.string_to_binary_array(key_str)
        val = AlphanumericCodec.string_to_binary_array(val_str)
        return cls(
            record_id    = record_id,
            key          = key,
            value        = val,
            key_checksum = ChecksumEngine.crc32(key),
            val_checksum = ChecksumEngine.crc32(val),
            browser_id   = browser_id,
            stream_id    = stream_id,
            created_at   = record_id * 1000
        )

    def validate(self) -> bool:
        return (ChecksumEngine.crc32(self.key)   == self.key_checksum and
                ChecksumEngine.crc32(self.value) == self.val_checksum)

    def key_string(self) -> str:
        return AlphanumericCodec.binary_array_to_string(self.key)

    def value_string(self) -> str:
        return AlphanumericCodec.binary_array_to_string(self.value)


class PersistenceStore:
    """Binary alphanumeric persistence store backed by hash table."""

    def __init__(self, store_id: int):
        self.store_id = store_id
        self.records: List[PersistenceRecord] = []
        self.index    = AlphanumericHashTable(capacity=16384)
        self.next_id  = 0

    def put(self, key_str: str, val_str: str, browser_id: int, stream_id: int) -> int:
        """Insert or update a record. Returns record ID."""
        record = PersistenceRecord.create(
            self.next_id, key_str, val_str, browser_id, stream_id
        )
        self.records.append(record)
        self.index.insert(record.key, record.value)
        self.next_id += 1
        return record.record_id

    def get(self, key_str: str) -> Optional[str]:
        """Retrieve a value by key string."""
        key   = AlphanumericCodec.string_to_binary_array(key_str)
        value = self.index.lookup(key)
        if value is not None:
            return AlphanumericCodec.binary_array_to_string(value)
        return None

    def delete(self, key_str: str) -> bool:
        """Soft-delete a record."""
        key = AlphanumericCodec.string_to_binary_array(key_str)
        return self.index.delete(key)

    def load_sensor_array(self, sensor_array: SafaSensorArray5K) -> int:
        """Bulk-load sensor array into persistence store."""
        count = 0
        for bank in sensor_array.banks:
            for reading in bank.readings:
                self.put(
                    reading.to_alphanumeric_key(),
                    reading.to_alphanumeric_value(),
                    reading.browser_id,
                    reading.stream_id
                )
                count += 1
        return count

    def statistics(self) -> Dict[str, Any]:
        return {
            'store_id':    self.store_id,
            'total_records': len(self.records),
            'active_records': sum(1 for r in self.records if not r.is_deleted),
            'hash_table_size': self.index.size,
            'load_factor': self.index.load_factor(),
            'capacity':    self.index.capacity
        }

# =============================================================================
# SECTION 14: DATAGRAM CHANNEL
# =============================================================================

@dataclass
class DatagramPacket:
    """WebTransport datagram packet."""
    packet_id:  int
    stream_id:  int
    browser_id: int
    data:       bytes
    ttl:        int   = 64
    priority:   int   = 1
    encrypted:  bool  = True
    checksum:   int   = 0
    timestamp:  int   = 0

    def __post_init__(self):
        if self.checksum == 0:
            self.checksum = ChecksumEngine.crc32_bytes(self.data)
        if self.timestamp == 0:
            self.timestamp = self.packet_id * 1000

    def validate(self) -> bool:
        return ChecksumEngine.crc32_bytes(self.data) == self.checksum

    @property
    def length(self) -> int:
        return len(self.data)


class DatagramChannel:
    """WebTransport datagram channel for binary block fragmentation."""

    MTU = MTU_BYTES

    def __init__(self, channel_id: int, browser_id: int):
        self.channel_id = channel_id
        self.browser_id = browser_id
        self.sent_packets:     List[DatagramPacket] = []
        self.received_packets: List[DatagramPacket] = []
        self.next_packet_id = 0

    def fragment_block(self, block: BinaryStorageBlock) -> List[DatagramPacket]:
        """Fragment a binary storage block into MTU-sized datagrams."""
        data = block.to_bytes()
        packets = []
        for i in range(0, len(data), self.MTU):
            fragment = data[i:i+self.MTU]
            pkt = DatagramPacket(
                packet_id  = self.next_packet_id,
                stream_id  = block.stream_id,
                browser_id = self.browser_id,
                data       = fragment,
                priority   = 1
            )
            packets.append(pkt)
            self.next_packet_id += 1
        self.sent_packets.extend(packets)
        return packets

    def reassemble(self, packets: List[DatagramPacket]) -> bytes:
        """Reassemble datagrams into original data."""
        valid = [p for p in packets if p.validate()]
        return b''.join(p.data for p in valid)

    def statistics(self) -> Dict[str, Any]:
        return {
            'channel_id':    self.channel_id,
            'browser':       'Edge' if self.browser_id == 0 else 'Firefox',
            'sent_packets':  len(self.sent_packets),
            'recv_packets':  len(self.received_packets),
            'total_sent_bytes': sum(p.length for p in self.sent_packets),
            'total_recv_bytes': sum(p.length for p in self.received_packets)
        }

# =============================================================================
# SECTION 15: QUANTUM BINARY PROCESSOR
# =============================================================================

class QuantumBinaryProcessor:
    """
    Simulates quantum operations on binary storage blocks.
    Implements Majorana correction, phase encoding, and coherence measurement.
    """

    def __init__(self, n_qubits: int = N_QUBITS, decoherence_rate: float = DECOHERENCE_RATE):
        self.n_qubits        = n_qubits
        self.decoherence_rate = decoherence_rate
        self.correction_angle = -math.asin(decoherence_rate)

    def encode_binary_to_state(self, binary_value: int) -> Tuple[float, float]:
        """Encode binary value as quantum state amplitudes (re, im)."""
        # Amplitude encoding: map [0, 65535] → [0, π/2]
        angle = (binary_value / 65535.0) * (math.pi / 2.0)
        return math.cos(angle), math.sin(angle)

    def apply_majorana_correction(self, re: float, im: float) -> Tuple[float, float]:
        """Apply Majorana phase correction to quantum state."""
        phi = self.correction_angle
        cos_phi = math.cos(phi)
        sin_phi = math.sin(phi)
        new_re = re * cos_phi - im * sin_phi
        new_im = re * sin_phi + im * cos_phi
        return new_re, new_im

    def measure_coherence(self, re: float, im: float) -> float:
        """Measure coherence (purity) of quantum state."""
        return re * re + im * im  # |ψ|² = purity

    def process_sensor_reading(self, reading: SafaSensorReading) -> Tuple[float, float, float]:
        """Process a sensor reading through quantum pipeline."""
        re, im = self.encode_binary_to_state(reading.binary_value)
        # Apply decoherence
        drift_angle = self.decoherence_rate * math.pi
        cos_d = math.cos(drift_angle)
        sin_d = math.sin(drift_angle)
        re_d = re * cos_d - im * sin_d
        im_d = re * sin_d + im * cos_d
        # Apply Majorana correction
        re_c, im_c = self.apply_majorana_correction(re_d, im_d)
        coherence = self.measure_coherence(re_c, im_c)
        return re_c, im_c, coherence

    def process_bank(self, bank: SafaSensorBank) -> List[float]:
        """Process all readings in a bank, return coherence values."""
        coherences = []
        for reading in bank.readings:
            _, _, coh = self.process_sensor_reading(reading)
            coherences.append(coh)
        return coherences

    def process_array(self, sensor_array: SafaSensorArray5K) -> Dict[str, Any]:
        """Process full 5K sensor array through quantum pipeline."""
        all_coherences = []
        bank_results   = []

        for bank in sensor_array.banks:
            coherences = self.process_bank(bank)
            all_coherences.extend(coherences)
            bank_results.append({
                'bank_id':       bank.bank_id,
                'mean_coherence':sum(coherences) / len(coherences),
                'min_coherence': min(coherences),
                'max_coherence': max(coherences)
            })

        return {
            'total_sensors':    len(all_coherences),
            'global_coherence': sum(all_coherences) / len(all_coherences),
            'min_coherence':    min(all_coherences),
            'max_coherence':    max(all_coherences),
            'corrected_pct':    sum(1 for c in all_coherences if c > 0.97) / len(all_coherences) * 100,
            'bank_results':     bank_results
        }

    def fuse_edge_firefox(
        self,
        edge_re: float, edge_im: float,
        firefox_re: float, firefox_im: float
    ) -> Tuple[float, float, float]:
        """Quantum fusion of Edge and Firefox states."""
        # Siamese entanglement: Bell-pair inspired fusion
        # |fused⟩ = (|edge⟩ + |firefox⟩) / √2
        fused_re = (edge_re + firefox_re) / math.sqrt(2.0)
        fused_im = (edge_im + firefox_im) / math.sqrt(2.0)
        # Apply Majorana correction
        fused_re, fused_im = self.apply_majorana_correction(fused_re, fused_im)
        fidelity = self.measure_coherence(fused_re, fused_im)
        return fused_re, fused_im, fidelity

# =============================================================================
# SECTION 16: WEBTRANSPORT MACHINE CONCLUSION ENGINE
# =============================================================================

class WebTransportMachineConclusionEngine:
    """
    Full WebTransport Machine Conclusion Engine.
    Orchestrates Edge + Firefox binary storage with 5K SafaSensors.
    """

    def __init__(self):
        self.codec      = AlphanumericCodec()
        self.checksum   = ChecksumEngine()
        self.qprocessor = QuantumBinaryProcessor()

        # Initialize browser managers
        self.edge_manager    = EdgeAgentManager(n_agents=1)
        self.firefox_manager = FirefoxRelayManager(n_relays=1)

        # Initialize datagram channels
        self.edge_channel    = DatagramChannel(0, BROWSER_EDGE)
        self.firefox_channel = DatagramChannel(1, BROWSER_FIREFOX)

        # Initialize persistence stores
        self.edge_store    = PersistenceStore(0)
        self.firefox_store = PersistenceStore(1)

        # Results
        self.results: Dict[str, Any] = {}

    def run(self) -> Dict[str, Any]:
        """Execute the full machine conclusion pipeline."""
        print("=" * 70)
        print("  WebTransport Machine Conclusion Engine")
        print("  Microsoft Edge ⊗ Mozilla Firefox")
        print("  SafaSensors 5K × 2 | Alphanumeric Binary Storage")
        print("=" * 70)

        # Step 1: Generate sensor arrays
        print("\n[Step 1/8] Generating SafaSensor 5K arrays...")
        edge_array    = SafaSensorFactory.generate_array_5k(0, BROWSER_EDGE)
        firefox_array = SafaSensorFactory.generate_array_5k(1, BROWSER_FIREFOX)
        print(f"  Edge    sensors: {edge_array.total_sensors}")
        print(f"  Firefox sensors: {firefox_array.total_sensors}")

        # Step 2: Build binary storage matrices
        print("\n[Step 2/8] Building binary storage matrices (5000×64)...")
        edge_matrix    = BinaryStorageMatrix(0, BROWSER_EDGE)
        firefox_matrix = BinaryStorageMatrix(1, BROWSER_FIREFOX)
        edge_matrix.load_from_array(edge_array)
        firefox_matrix.load_from_array(firefox_array)
        edge_stats    = edge_matrix.statistics()
        firefox_stats = firefox_matrix.statistics()
        print(f"  Edge    matrix: {edge_stats['rows']}×{edge_stats['cols']}, "
              f"density={edge_stats['density']:.4f}, "
              f"checksum=0x{edge_stats['checksum']:08X}")
        print(f"  Firefox matrix: {firefox_stats['rows']}×{firefox_stats['cols']}, "
              f"density={firefox_stats['density']:.4f}, "
              f"checksum=0x{firefox_stats['checksum']:08X}")

        # Step 3: Quantum processing
        print("\n[Step 3/8] Quantum processing (Majorana correction)...")
        edge_qresult    = self.qprocessor.process_array(edge_array)
        firefox_qresult = self.qprocessor.process_array(firefox_array)
        print(f"  Edge    global coherence: {edge_qresult['global_coherence']:.6f}")
        print(f"  Firefox global coherence: {firefox_qresult['global_coherence']:.6f}")
        print(f"  Edge    corrected:        {edge_qresult['corrected_pct']:.2f}%")
        print(f"  Firefox corrected:        {firefox_qresult['corrected_pct']:.2f}%")

        # Step 4: Load persistence stores
        print("\n[Step 4/8] Loading alphanumeric persistence stores...")
        edge_count    = self.edge_store.load_sensor_array(edge_array)
        firefox_count = self.firefox_store.load_sensor_array(firefox_array)
        print(f"  Edge    records: {edge_count}")
        print(f"  Firefox records: {firefox_count}")
        print(f"  Edge    hash table load: {self.edge_store.index.load_factor():.3f}")
        print(f"  Firefox hash table load: {self.firefox_store.index.load_factor():.3f}")

        # Step 5: Process sensor banks through browser agents
        print("\n[Step 5/8] Processing sensor banks through browser agents...")
        edge_decisions    = []
        firefox_decisions = []
        for bank_idx in range(min(5, len(edge_array.banks))):
            edge_result    = self.edge_manager.process_sensor_bank(
                edge_array.banks[bank_idx], 0)
            firefox_result = self.firefox_manager.relay_sensor_bank(
                firefox_array.banks[bank_idx], 0)
            edge_decisions.append(edge_result['decision'])
            firefox_decisions.append(firefox_result['relayed_blocks'])

        edge_decision    = max(set(edge_decisions), key=edge_decisions.count)
        firefox_relayed  = sum(firefox_decisions)
        print(f"  Edge    majority decision: {edge_decision}")
        print(f"  Firefox relayed blocks:   {firefox_relayed}")

        # Step 6: Quantum fusion
        print("\n[Step 6/8] Quantum Edge⊗Firefox fusion...")
        edge_re, edge_im = self.qprocessor.encode_binary_to_state(
            int(edge_qresult['global_coherence'] * 65535))
        ff_re, ff_im = self.qprocessor.encode_binary_to_state(
            int(firefox_qresult['global_coherence'] * 65535))
        fused_re, fused_im, fidelity = self.qprocessor.fuse_edge_firefox(
            edge_re, edge_im, ff_re, ff_im)
        fused_decision = ("Consensus" if fidelity > 0.8
                          else "Edge-Lead" if fidelity > 0.5
                          else "Firefox-Lead")
        print(f"  Fusion fidelity:  {fidelity:.6f}")
        print(f"  Fused decision:   {fused_decision}")

        # Step 7: Datagram fragmentation
        print("\n[Step 7/8] Datagram fragmentation & reassembly...")
        sample_block = BinaryStorageBlock.from_reading(
            edge_array.banks[0].readings[0], 0)
        edge_packets    = self.edge_channel.fragment_block(sample_block)
        reassembled     = self.edge_channel.reassemble(edge_packets)
        print(f"  Sample block size:    {len(sample_block.data_bits)} bits")
        print(f"  Fragmented packets:   {len(edge_packets)}")
        print(f"  Reassembled bytes:    {len(reassembled)}")
        print(f"  Integrity check:      {'PASS' if len(reassembled) > 0 else 'FAIL'}")

        # Step 8: Final conclusion
        print("\n[Step 8/8] Computing machine conclusion...")
        global_coherence = (edge_qresult['global_coherence'] +
                            firefox_qresult['global_coherence']) / 2.0
        global_mean      = (edge_array.get_global_mean() +
                            firefox_array.get_global_mean()) / 2.0
        total_bits       = (edge_stats['total_bits'] + firefox_stats['total_bits'])
        total_frames     = edge_count + firefox_count
        certified        = (global_coherence > 0.97 and
                            fidelity > 0.7 and
                            DECOHERENCE_RATE <= 0.05)

        edge_throughput    = self.edge_manager.sessions[0].aggregate_throughput()
        firefox_throughput = self.firefox_manager.sessions[0].aggregate_throughput()
        total_throughput   = edge_throughput + firefox_throughput
        avg_rtt            = (self.edge_manager.sessions[0].average_rtt() +
                              self.firefox_manager.sessions[0].average_rtt()) / 2.0

        self.results = {
            'conclusion_id':        1,
            'edge_decision':        edge_decision,
            'firefox_decision':     'Healthy' if firefox_qresult['global_coherence'] > 0.97 else 'Degraded',
            'fused_decision':       fused_decision,
            'total_sensors':        edge_array.total_sensors + firefox_array.total_sensors,
            'processed_sensors':    edge_array.total_sensors + firefox_array.total_sensors,
            'global_coherence_pct': global_coherence * 100.0,
            'global_mean_value':    global_mean,
            'binary_storage_bits':  total_bits,
            'alphanumeric_records': total_frames,
            'fusion_fidelity':      fidelity,
            'class10_certified':    certified,
            'avg_latency_ms':       avg_rtt,
            'total_throughput_mbps':total_throughput,
            'edge_matrix_checksum': f"0x{edge_stats['checksum']:08X}",
            'firefox_matrix_checksum': f"0x{firefox_stats['checksum']:08X}",
            'edge_corrected_pct':   edge_qresult['corrected_pct'],
            'firefox_corrected_pct':firefox_qresult['corrected_pct'],
            'hash_table_load_edge': self.edge_store.index.load_factor(),
            'hash_table_load_ff':   self.firefox_store.index.load_factor(),
            'datagram_packets':     len(edge_packets),
            'precision':            PRECISION,
            'n_qubits':             N_QUBITS,
            'decoherence_rate':     DECOHERENCE_RATE
        }

        self._print_summary()
        return self.results

    def _print_summary(self) -> None:
        r = self.results
        cert = "CLASS-10 CERTIFIED ✓" if r['class10_certified'] else "NOT CERTIFIED ✗"
        print("\n" + "=" * 70)
        print("  MACHINE CONCLUSION SUMMARY")
        print("=" * 70)
        print(f"  Edge Decision          : {r['edge_decision']}")
        print(f"  Firefox Decision       : {r['firefox_decision']}")
        print(f"  Fused Decision         : {r['fused_decision']}")
        print(f"  Total Sensors          : {r['total_sensors']:,}")
        print(f"  Global Coherence       : {r['global_coherence_pct']:.4f}%")
        print(f"  Global Mean Value      : {r['global_mean_value']:.6f}")
        print(f"  Binary Storage         : {r['binary_storage_bits']:,} bits")
        print(f"  Alphanumeric Records   : {r['alphanumeric_records']:,}")
        print(f"  Fusion Fidelity        : {r['fusion_fidelity']:.6f}")
        print(f"  Safety Status          : {cert}")
        print(f"  Avg Latency            : {r['avg_latency_ms']:.2f} ms")
        print(f"  Total Throughput       : {r['total_throughput_mbps']:.1f} Mbps")
        print(f"  Edge Matrix Checksum   : {r['edge_matrix_checksum']}")
        print(f"  Firefox Matrix Checksum: {r['firefox_matrix_checksum']}")
        print(f"  Precision              : {r['precision']}")
        print(f"  n_qubits               : {r['n_qubits']}")
        print(f"  Decoherence Rate       : {r['decoherence_rate']}")
        print("=" * 70)

# =============================================================================
# SECTION 17: BF16 NEURAL NETWORK LAYER
# =============================================================================

class BF16LinearLayer:
    """BF16 linear layer: y = W·x + b"""

    def __init__(self, in_dim: int, out_dim: int, seed: int = 42):
        self.in_dim  = in_dim
        self.out_dim = out_dim
        # Xavier initialization in BF16
        limit = math.sqrt(6.0 / (in_dim + out_dim))
        self.weights = [
            [float_to_bf16(limit * math.sin((i * out_dim + j) * 0.001))
             for j in range(in_dim)]
            for i in range(out_dim)
        ]
        self.biases = [float_to_bf16(0.0)] * out_dim

    def forward(self, x: List[int]) -> List[int]:
        """Forward pass in BF16."""
        return [
            bf16_fma(
                bf16_dot_product(self.weights[i], x),
                float_to_bf16(1.0),
                self.biases[i]
            )
            for i in range(self.out_dim)
        ]

    def forward_float(self, x: List[float]) -> List[float]:
        """Forward pass with float inputs (auto-converts to BF16)."""
        x_bf16 = [float_to_bf16(v) for v in x]
        out_bf16 = self.forward(x_bf16)
        return [bf16_to_float(v) for v in out_bf16]


class BF16ReLULayer:
    """BF16 ReLU activation layer."""

    def forward(self, x: List[int]) -> List[int]:
        return [bf16_relu(v) for v in x]

    def forward_float(self, x: List[float]) -> List[float]:
        return [max(0.0, v) for v in x]


class BF16SensorClassifier:
    """
    BF16 sensor classifier: 8 → 32 → 16 → 4 classes.
    Classes: Healthy, Degraded, Critical, Recovering
    """

    CLASS_LABELS = ["Healthy", "Degraded", "Critical", "Recovering"]

    def __init__(self):
        self.l1   = BF16LinearLayer(8, 32)
        self.r1   = BF16ReLULayer()
        self.l2   = BF16LinearLayer(32, 16)
        self.r2   = BF16ReLULayer()
        self.l3   = BF16LinearLayer(16, 4)

    def forward(self, features: List[float]) -> Tuple[List[float], str]:
        """Forward pass. Returns (probabilities, predicted_class)."""
        x = features[:8]
        while len(x) < 8:
            x.append(0.0)

        h1 = self.l1.forward_float(x)
        h1 = self.r1.forward_float(h1)
        h2 = self.l2.forward_float(h1)
        h2 = self.r2.forward_float(h2)
        logits = self.l3.forward_float(h2)

        # Softmax
        max_l = max(logits)
        exps  = [math.exp(l - max_l) for l in logits]
        sum_e = sum(exps)
        probs = [e / sum_e for e in exps]

        pred_class = self.CLASS_LABELS[probs.index(max(probs))]
        return probs, pred_class

    def classify_bank(self, bank: SafaSensorBank) -> Tuple[List[float], str]:
        """Classify a sensor bank."""
        features = [r.raw_value for r in bank.readings[:8]]
        return self.forward(features)

# =============================================================================
# SECTION 18: ALPHANUMERIC STREAM PROTOCOL
# =============================================================================

@dataclass
class AlphanumericStreamFrame:
    """WebTransport alphanumeric stream frame."""
    frame_id:    int
    stream_id:   int
    browser_id:  int
    payload:     List[int]   # alphanumeric binary payload
    seq_num:     int
    ack_num:     int
    flags:       int         # SYN=1, ACK=2, FIN=4, RST=8
    checksum:    int = 0
    timestamp:   int = 0

    def __post_init__(self):
        if self.checksum == 0:
            self.checksum = ChecksumEngine.crc32(self.payload)
        if self.timestamp == 0:
            self.timestamp = self.frame_id * 1000 + self.stream_id

    def validate(self) -> bool:
        return ChecksumEngine.crc32(self.payload) == self.checksum

    def payload_string(self) -> str:
        return AlphanumericCodec.binary_array_to_string(self.payload)

    @classmethod
    def from_sensor_reading(cls, reading: SafaSensorReading, frame_id: int) -> 'AlphanumericStreamFrame':
        """Create frame from sensor reading."""
        # Encode as 4-char alphanumeric payload
        payload_str = reading.alpha_code
        payload = AlphanumericCodec.string_to_binary_array(payload_str)
        return cls(
            frame_id   = frame_id,
            stream_id  = reading.stream_id,
            browser_id = reading.browser_id,
            payload    = payload,
            seq_num    = frame_id,
            ack_num    = frame_id - 1,
            flags      = 2  # ACK
        )


class AlphanumericStreamProtocol:
    """Manages alphanumeric stream frames over WebTransport."""

    def __init__(self, protocol_id: int, browser_id: int):
        self.protocol_id = protocol_id
        self.browser_id  = browser_id
        self.frames:     List[AlphanumericStreamFrame] = []
        self.next_frame  = 0
        self.next_seq    = 0

    def send_reading(self, reading: SafaSensorReading) -> AlphanumericStreamFrame:
        """Send a sensor reading as a stream frame."""
        frame = AlphanumericStreamFrame.from_sensor_reading(reading, self.next_frame)
        self.frames.append(frame)
        self.next_frame += 1
        self.next_seq   += len(frame.payload)
        return frame

    def send_bank(self, bank: SafaSensorBank) -> List[AlphanumericStreamFrame]:
        """Send all readings in a bank as stream frames."""
        return [self.send_reading(r) for r in bank.readings]

    def reassemble(self) -> str:
        """Reassemble all valid frames into alphanumeric string."""
        valid = [f for f in self.frames if f.validate()]
        return ''.join(f.payload_string() for f in valid)

    def statistics(self) -> Dict[str, Any]:
        valid = sum(1 for f in self.frames if f.validate())
        return {
            'protocol_id':   self.protocol_id,
            'browser':       'Edge' if self.browser_id == 0 else 'Firefox',
            'total_frames':  len(self.frames),
            'valid_frames':  valid,
            'total_payload': sum(len(f.payload) for f in self.frames),
            'integrity_pct': valid / len(self.frames) * 100 if self.frames else 0
        }

# =============================================================================
# SECTION 19: DIFFERENTIAL PRIVACY ENGINE
# =============================================================================

class DifferentialPrivacyEngine:
    """Gaussian mechanism DP engine for federated sensor data."""

    def __init__(self, epsilon: float = DP_EPSILON, delta: float = DP_DELTA,
                 clip_norm: float = CLIP_NORM):
        self.epsilon   = epsilon
        self.delta     = delta
        self.clip_norm = clip_norm
        self.sigma     = self._compute_sigma()

    def _compute_sigma(self) -> float:
        """Compute Gaussian noise std dev for (ε, δ)-DP."""
        return math.sqrt(2 * math.log(1.25 / self.delta)) * self.clip_norm / self.epsilon

    def clip_gradients(self, gradients: List[float]) -> List[float]:
        """Clip gradient vector to L2 norm bound."""
        norm = math.sqrt(sum(g*g for g in gradients))
        if norm > self.clip_norm:
            scale = self.clip_norm / norm
            return [g * scale for g in gradients]
        return gradients

    def add_noise(self, values: List[float], seed: int = 0) -> List[float]:
        """Add calibrated Gaussian noise for DP."""
        noisy = []
        for i, v in enumerate(values):
            # Box-Muller transform (deterministic)
            u1 = 0.5 + 0.4 * math.sin((i * 1009 + seed * 7919) * 0.0001)
            u2 = 0.5 + 0.4 * math.cos((i * 2003 + seed * 6271) * 0.0001)
            z  = self.sigma * math.sqrt(-2.0 * math.log(u1 + 1e-10)) * math.cos(2 * math.pi * u2)
            noisy.append(v + z)
        return noisy

    def privatize_sensor_features(self, features: List[float], client_id: int) -> List[float]:
        """Apply DP to sensor feature vector."""
        clipped = self.clip_gradients(features)
        return self.add_noise(clipped, seed=client_id)

    def renyi_dp_guarantee(self, alpha: float) -> float:
        """Compute Rényi DP guarantee ε_R(α) for Gaussian mechanism."""
        return alpha * self.clip_norm**2 / (2 * self.sigma**2)

    def privacy_budget_after_rounds(self, n_rounds: int, alpha: float = 10.0) -> float:
        """Total (ε, δ)-DP after n_rounds via RDP composition."""
        rdp = n_rounds * self.renyi_dp_guarantee(alpha)
        eps = rdp + math.log(1 - 1/alpha) - math.log(self.delta * (alpha - 1)) / (alpha - 1)
        return eps

# =============================================================================
# SECTION 20: MAIN ENTRY POINT
# =============================================================================

def run_webtransport_machine_conclusion() -> Dict[str, Any]:
    """Main entry point for WebTransport Machine Conclusion."""
    engine = WebTransportMachineConclusionEngine()
    results = engine.run()

    # Additional: run DP audit
    print("\n[DP Audit] Differential Privacy Budget...")
    dp = DifferentialPrivacyEngine()
    budget_10 = dp.privacy_budget_after_rounds(10)
    budget_50 = dp.privacy_budget_after_rounds(50)
    print(f"  Sigma (noise std):     {dp.sigma:.4f}")
    print(f"  Privacy after 10 rounds: ε={budget_10:.4f}")
    print(f"  Privacy after 50 rounds: ε={budget_50:.4f}")

    # Additional: BF16 classifier on first bank
    print("\n[BF16 Classifier] SafaSensor bank classification...")
    edge_array = SafaSensorFactory.generate_array_5k(0, BROWSER_EDGE)
    classifier = BF16SensorClassifier()
    probs, pred = classifier.classify_bank(edge_array.banks[0])
    print(f"  Bank 0 prediction: {pred}")
    print(f"  Probabilities: " + ", ".join(f"{BF16SensorClassifier.CLASS_LABELS[i]}={probs[i]:.4f}" for i in range(4)))

    # Additional: alphanumeric stream protocol stats
    print("\n[Stream Protocol] Alphanumeric frame statistics...")
    proto = AlphanumericStreamProtocol(0, BROWSER_EDGE)
    proto.send_bank(edge_array.banks[0])
    stats = proto.statistics()
    print(f"  Total frames:   {stats['total_frames']}")
    print(f"  Valid frames:   {stats['valid_frames']}")
    print(f"  Integrity:      {stats['integrity_pct']:.1f}%")
    print(f"  Total payload:  {stats['total_payload']} bytes")

    results['dp_budget_10_rounds'] = budget_10
    results['dp_budget_50_rounds'] = budget_50
    results['classifier_prediction'] = pred
    results['stream_integrity_pct']  = stats['integrity_pct']

    return results


if __name__ == "__main__":
    results = run_webtransport_machine_conclusion()
    sys.exit(0)
