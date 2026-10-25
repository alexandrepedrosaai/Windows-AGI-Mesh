//! # ZIB Wire Protocol
//!
//! Binary wire format for ZIB messages transmitted over sockets,
//! shared memory, or inter-process channels.
//!
//! ## Frame Format
//!
//! ```text
//! ┌─────────────────────────────────────────────────────┐
//! │ Magic (4B) │ Version (1B) │ Flags (1B) │ Len (4B)  │
//! ├─────────────────────────────────────────────────────┤
//! │ Checksum (4B) │ Sequence (8B) │ Reserved (4B)       │
//! ├─────────────────────────────────────────────────────┤
//! │ Payload (variable, bincode-encoded ZMessage)        │
//! └─────────────────────────────────────────────────────┘
//! ```

use crate::message::ZMessage;
use crate::error::ZibError;
use crate::codec::{encode, decode, checksum, CodecFormat};

/// ZIB wire frame magic bytes: "ZIB\x03"
pub const FRAME_MAGIC: [u8; 4] = [b'Z', b'I', b'B', 0x03];

/// ZIB wire protocol version
pub const WIRE_VERSION: u8 = 1;

/// Frame flags
pub mod flags {
    pub const COMPRESSED: u8 = 0b0000_0001;
    pub const ENCRYPTED:  u8 = 0b0000_0010;
    pub const FRAGMENTED: u8 = 0b0000_0100;
    pub const LAST_FRAG:  u8 = 0b0000_1000;
}

/// A ZIB wire frame
#[derive(Debug, Clone)]
pub struct WireFrame {
    /// Magic bytes
    pub magic: [u8; 4],
    /// Protocol version
    pub version: u8,
    /// Frame flags
    pub flags: u8,
    /// Payload length in bytes
    pub payload_len: u32,
    /// CRC32-like checksum of payload
    pub checksum: u32,
    /// Frame sequence number
    pub sequence: u64,
    /// Reserved bytes (future use)
    pub reserved: [u8; 4],
    /// Encoded ZMessage payload
    pub payload: Vec<u8>,
}

impl WireFrame {
    /// Encode a ZMessage into a wire frame
    pub fn encode(msg: &ZMessage, sequence: u64) -> Result<Self, ZibError> {
        let payload = encode(msg, CodecFormat::Bincode)?;
        let chk = checksum(&payload);
        let mut flags = 0u8;
        if msg.header.compressed { flags |= flags::COMPRESSED; }
        if msg.header.encrypted  { flags |= flags::ENCRYPTED; }

        Ok(Self {
            magic: FRAME_MAGIC,
            version: WIRE_VERSION,
            flags,
            payload_len: payload.len() as u32,
            checksum: chk,
            sequence,
            reserved: [0u8; 4],
            payload,
        })
    }

    /// Serialize the frame to bytes for transmission
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::with_capacity(26 + self.payload.len());
        buf.extend_from_slice(&self.magic);
        buf.push(self.version);
        buf.push(self.flags);
        buf.extend_from_slice(&self.payload_len.to_be_bytes());
        buf.extend_from_slice(&self.checksum.to_be_bytes());
        buf.extend_from_slice(&self.sequence.to_be_bytes());
        buf.extend_from_slice(&self.reserved);
        buf.extend_from_slice(&self.payload);
        buf
    }

    /// Deserialize a frame from bytes
    pub fn from_bytes(data: &[u8]) -> Result<Self, ZibError> {
        if data.len() < 26 {
            return Err(ZibError::CodecError {
                reason: format!("frame too short: {} bytes", data.len()),
            });
        }

        let magic: [u8; 4] = data[0..4].try_into().unwrap();
        if magic != FRAME_MAGIC {
            return Err(ZibError::CodecError {
                reason: "invalid frame magic".into(),
            });
        }

        let version = data[4];
        if version != WIRE_VERSION {
            return Err(ZibError::ProtocolVersionMismatch {
                expected: WIRE_VERSION,
                got: version,
            });
        }

        let flags       = data[5];
        let payload_len = u32::from_be_bytes(data[6..10].try_into().unwrap());
        let chk         = u32::from_be_bytes(data[10..14].try_into().unwrap());
        let sequence    = u64::from_be_bytes(data[14..22].try_into().unwrap());
        let reserved: [u8; 4] = data[22..26].try_into().unwrap();

        if data.len() < 26 + payload_len as usize {
            return Err(ZibError::CodecError {
                reason: "frame payload truncated".into(),
            });
        }

        let payload = data[26..26 + payload_len as usize].to_vec();

        // Verify checksum
        if checksum(&payload) != chk {
            return Err(ZibError::CodecError {
                reason: "frame checksum mismatch".into(),
            });
        }

        Ok(Self {
            magic,
            version,
            flags,
            payload_len,
            checksum: chk,
            sequence,
            reserved,
            payload,
        })
    }

    /// Decode the ZMessage from this frame
    pub fn decode_message(&self) -> Result<ZMessage, ZibError> {
        decode(&self.payload, CodecFormat::Bincode)
    }

    /// Whether this frame is compressed
    pub fn is_compressed(&self) -> bool {
        self.flags & flags::COMPRESSED != 0
    }

    /// Whether this frame is encrypted
    pub fn is_encrypted(&self) -> bool {
        self.flags & flags::ENCRYPTED != 0
    }

    /// Whether this frame is a fragment
    pub fn is_fragment(&self) -> bool {
        self.flags & flags::FRAGMENTED != 0
    }

    /// Whether this is the last fragment
    pub fn is_last_fragment(&self) -> bool {
        self.flags & flags::LAST_FRAG != 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;
    use zenith_abi::domain::Domain;
    use crate::topics::Topic;

    fn make_msg() -> ZMessage {
        ZMessage::new(
            Uuid::new_v4(), Domain::Windows, Some(Domain::AI),
            Topic::InferenceRequest, b"inference-payload-data".to_vec(),
        )
    }

    #[test]
    fn wire_frame_roundtrip() {
        let msg = make_msg();
        let frame = WireFrame::encode(&msg, 42).unwrap();
        let bytes = frame.to_bytes();
        let decoded_frame = WireFrame::from_bytes(&bytes).unwrap();
        let decoded_msg = decoded_frame.decode_message().unwrap();

        assert_eq!(decoded_frame.sequence, 42);
        assert_eq!(decoded_msg.id(), msg.id());
        assert_eq!(decoded_msg.topic(), msg.topic());
        assert_eq!(decoded_msg.payload, msg.payload);
    }

    #[test]
    fn wire_frame_bad_magic() {
        let mut bytes = vec![0u8; 30];
        bytes[0] = b'X'; // wrong magic
        assert!(WireFrame::from_bytes(&bytes).is_err());
    }

    #[test]
    fn wire_frame_checksum_tamper() {
        let msg = make_msg();
        let frame = WireFrame::encode(&msg, 1).unwrap();
        let mut bytes = frame.to_bytes();
        // Tamper with payload
        if let Some(b) = bytes.last_mut() {
            *b ^= 0xFF;
        }
        assert!(WireFrame::from_bytes(&bytes).is_err());
    }

    #[test]
    fn wire_frame_too_short() {
        assert!(WireFrame::from_bytes(&[0u8; 10]).is_err());
    }
}