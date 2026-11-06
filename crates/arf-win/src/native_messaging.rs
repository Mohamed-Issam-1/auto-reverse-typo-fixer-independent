//! Read-only Native Messaging transport.
//! This is NOT an authorization channel for text correction.

use std::io::{self, Error, ErrorKind, Read, Write};

const MAX_REQUEST_SIZE: usize = 4096;
const HEALTH_REQUEST: &[u8] = br#"{"kind":"arf.health.v1"}"#;
const HEALTH_RESPONSE: &[u8] =
    br#"{"kind":"arf.health.v1","status":"diagnostic-only","correction_enabled":false}"#;

/// Process one length-prefixed health request.
/// No hooks, clipboard, text capture, focus checks, or SendInput.
/// Unknown messages receive no response and are rejected.
pub fn serve_one<R: Read, W: Write>(reader: &mut R, writer: &mut W) -> io::Result<bool> {
    let mut header = [0u8; 4];

    if reader.read(&mut header[..1])? == 0 {
        return Ok(false);
    }

    reader.read_exact(&mut header[1..])?;

    let length = u32::from_le_bytes(header) as usize;

    if length == 0 || length > MAX_REQUEST_SIZE {
        return Err(Error::new(
            ErrorKind::InvalidData,
            "invalid native message length",
        ));
    }

    let mut request = vec![0u8; length];
    reader.read_exact(&mut request)?;

    if request.as_slice() != HEALTH_REQUEST {
        return Err(Error::new(
            ErrorKind::PermissionDenied,
            "unsupported native message",
        ));
    }

    let response_length = HEALTH_RESPONSE.len() as u32;

    writer.write_all(&response_length.to_le_bytes())?;
    writer.write_all(HEALTH_RESPONSE)?;
    writer.flush()?;

    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn frame(body: &[u8]) -> Vec<u8> {
        let mut result = (body.len() as u32).to_le_bytes().to_vec();
        result.extend_from_slice(body);
        result
    }

    #[test]
    fn valid_health_roundtrip() {
        let mut input = Cursor::new(frame(HEALTH_REQUEST));
        let mut output = Vec::new();

        assert!(serve_one(&mut input, &mut output).unwrap());

        let size = u32::from_le_bytes(output[..4].try_into().unwrap()) as usize;

        assert_eq!(size, HEALTH_RESPONSE.len());
        assert_eq!(&output[4..], HEALTH_RESPONSE);
    }

    #[test]
    fn clean_eof_no_response() {
        let mut input = Cursor::new(Vec::<u8>::new());
        let mut output = Vec::new();

        assert!(!serve_one(&mut input, &mut output).unwrap());
        assert!(output.is_empty());
    }

    #[test]
    fn truncated_header_rejected() {
        let mut input = Cursor::new(vec![1u8, 0u8]);
        let mut output = Vec::new();

        let error = serve_one(&mut input, &mut output).unwrap_err();

        assert_eq!(error.kind(), ErrorKind::UnexpectedEof);
        assert!(output.is_empty());
    }

    #[test]
    fn oversize_rejected() {
        let size = (MAX_REQUEST_SIZE as u32 + 1).to_le_bytes();

        let mut input = Cursor::new(size.to_vec());
        let mut output = Vec::new();

        let error = serve_one(&mut input, &mut output).unwrap_err();

        assert_eq!(error.kind(), ErrorKind::InvalidData);
        assert!(output.is_empty());
    }

    #[test]
    fn unknown_request_rejected() {
        let mut input = Cursor::new(frame(br#"{"kind":"arf.correct.v1"}"#));
        let mut output = Vec::new();

        let error = serve_one(&mut input, &mut output).unwrap_err();

        assert_eq!(error.kind(), ErrorKind::PermissionDenied);
        assert!(output.is_empty());
    }

    #[test]
    fn truncated_body_rejected() {
        let mut bytes = (HEALTH_REQUEST.len() as u32).to_le_bytes().to_vec();

        bytes.push(b'{');

        let mut input = Cursor::new(bytes);
        let mut output = Vec::new();

        let error = serve_one(&mut input, &mut output).unwrap_err();

        assert_eq!(error.kind(), ErrorKind::UnexpectedEof);
        assert!(output.is_empty());
    }
}
