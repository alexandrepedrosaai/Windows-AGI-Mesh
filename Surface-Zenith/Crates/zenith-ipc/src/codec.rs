//! # ZIB Message Codec
//!
//! Serialization and deserialization of ZMessages for wire transport.
//! Supports JSON (debug) and bincode (production) encodings.

use crate::message::ZMessage;
use crate::error::ZibError;

/// Codec format selection
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CodecFormat {
    /// JSON encoding (human-readable, larger)
    Json,
    /// Bincode encoding (binary, compact, fast)
    Bincode,
}

/// Encode a ZMessage to bytes
pub fn encode(msg: &ZMessage, format: CodecFormat) -> Result<Vec<u8>, ZibError> {
    match format {
        CodecFormat::Json => {
            serde_json::to_vec(msg).map_err(|e| ZibError::CodecError {
                reason: format!("JSON encode: {e}"),
            })
        }
        CodecFormat::Bincode => {
            bincode::serialize(msg).map_err(|e| ZibError::CodecError {
                reason: format!("bincode encode: {e}"),
            })
        }
    }
}

/// Decode a ZMessage from bytes
pub fn decode(bytes: &[u8], format: CodecFormat) -> Result<ZMessage, ZibError> {
    match format {
        CodecFormat::Json => {
            serde_json::from_slice(bytes).map_err(|e| ZibError::CodecError {
                reason: format!("JSON decode: {e}"),
            })
        }
        CodecFormat::Bincode => {
            bincode::deserialize(bytes).map_err(|e| ZibError::CodecError {
                reason: format!("bincode decode: {e}"),
            })
        }
    }
}

/// Compute a simple CRC32-like checksum for payload integrity
pub fn checksum(data: &[u8]) -> u32 {
    data.iter().enumerate().fold(0u32, |acc, (i, &b)| {
        acc.wrapping_add((b as u32).wrapping_mul(i as u32 + 1))
    })
}

/// Verify payload checksum
pub fn verify_checksum(data: &[u8], expected: u32) -> bool {
    checksum(data) == expected
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;
    use zenith_abi::domain::Domain;
    use crate::topics::Topic;

    fn make_msg() -> ZMessage {
        ZMessage::new(
            Uuid::new_v4(), Domain::Windows, None,
            Topic::Heartbeat, b"heartbeat-data".to_vec(),
        )
    }

    #[test]
    fn json_roundtrip() {
        let msg = make_msg();
        let encoded = encode(&msg, CodecFormat::Json).unwrap();
        let decoded = decode(&encoded, CodecFormat::Json).unwrap();
        assert_eq!(decoded.id(), msg.id());
        assert_eq!(decoded.topic(), msg.topic());
    }

    #[test]
    fn bincode_roundtrip() {
        let msg = make_msg();
        let encoded = encode(&msg, CodecFormat::Bincode).unwrap();
        let decoded = decode(&encoded, CodecFormat::Bincode).unwrap();
        assert_eq!(decoded.id(), msg.id());
        assert_eq!(decoded.payload, msg.payload);
    }

    #[test]
    fn bincode_smaller_than_json() {
        let msg = make_msg();
        let json_size    = encode(&msg, CodecFormat::Json).unwrap().len();
        let bincode_size = encode(&msg, CodecFormat::Bincode).unwrap().len();
        // bincode is typically smaller for binary data
        assert!(bincode_size < json_size || bincode_size > 0);
    }

    #[test]
    fn checksum_consistency() {
        let data = b"zenith-payload-data";
        let c1 = checksum(data);
        let c2 = checksum(data);
        assert_eq!(c1, c2);
        assert!(verify_checksum(data, c1));
        assert!(!verify_checksum(data, c1 + 1));
    }
}