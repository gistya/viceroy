//===----------------------------------------------------------------------===//
// Viceroy — UTF-8  (WHATWG §"UTF-8 decoder" / "UTF-8 encoder")
//
// Our own copy of the UTF-8 state machine — no Foundation, no stdlib coupling
// beyond `Unicode.Scalar`. Error handling follows the Unicode 3.9 "maximal
// subpart" recommendation exactly as WHATWG specifies, so U+FFFD lands in the
// same places every browser puts it.
//===----------------------------------------------------------------------===//

@usableFromInline
struct UTF8Decoder: ByteHandler {
    @usableFromInline var codepoint: UInt32 = 0
    @usableFromInline var bytesNeeded: UInt8 = 0
    @usableFromInline var bytesSeen: UInt8 = 0
    @usableFromInline var lower: UInt8 = 0x80
    @usableFromInline var upper: UInt8 = 0xBF

    @inlinable init() {}

    @inlinable
    mutating func reset() {
        codepoint = 0; bytesNeeded = 0; bytesSeen = 0; lower = 0x80; upper = 0xBF
    }

    @inlinable
    mutating func handle(_ byte: UInt8) -> ByteResult {
        if bytesNeeded == 0 {
            switch byte {
            case 0x00...0x7F:
                return .scalar(Unicode.Scalar(byte))
            case 0xC2...0xDF:
                bytesNeeded = 1; codepoint = UInt32(byte & 0x1F)
            case 0xE0...0xEF:
                if byte == 0xE0 { lower = 0xA0 }
                if byte == 0xED { upper = 0x9F }
                bytesNeeded = 2; codepoint = UInt32(byte & 0x0F)
            case 0xF0...0xF4:
                if byte == 0xF0 { lower = 0x90 }
                if byte == 0xF4 { upper = 0x8F }
                bytesNeeded = 3; codepoint = UInt32(byte & 0x07)
            default:
                return .error
            }
            return .again
        }
        // Continuation expected.
        if byte < lower || byte > upper {
            reset()
            // The offending byte is reprocessed as a fresh lead (WHATWG "prepend").
            return .errorPrepend([byte])
        }
        lower = 0x80; upper = 0xBF
        codepoint = (codepoint << 6) | UInt32(byte & 0x3F)
        bytesSeen += 1
        if bytesSeen != bytesNeeded { return .again }
        let cp = codepoint
        reset()
        // cp is guaranteed a valid scalar by the boundary checks above.
        return .scalar(Unicode.Scalar(cp)!)
    }

    @inlinable
    mutating func handleEOF() -> ByteResult {
        if bytesNeeded != 0 { reset(); return .error }
        return .again
    }
}

@usableFromInline
struct UTF8Encoder: ScalarHandler {
    @inlinable init() {}

    @inlinable
    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult {
        let v = scalar.value
        switch v {
        case 0x0000...0x007F:
            out.append(UInt8(v))
        case 0x0080...0x07FF:
            out.append(UInt8(0xC0 | (v >> 6)))
            out.append(UInt8(0x80 | (v & 0x3F)))
        case 0x0800...0xFFFF:
            out.append(UInt8(0xE0 | (v >> 12)))
            out.append(UInt8(0x80 | ((v >> 6) & 0x3F)))
            out.append(UInt8(0x80 | (v & 0x3F)))
        default:
            out.append(UInt8(0xF0 | (v >> 18)))
            out.append(UInt8(0x80 | ((v >> 12) & 0x3F)))
            out.append(UInt8(0x80 | ((v >> 6) & 0x3F)))
            out.append(UInt8(0x80 | (v & 0x3F)))
        }
        return .ok
    }
}

// MARK: - Static entry point

extension Encoding {
    /// UTF-8, resolved statically. Links only the UTF-8 path — no tables at all.
    /// NB: `Swift.UTF8` is spelled explicitly below; inside `extension Encoding`
    /// a bare `UTF8` would resolve to this very namespace.
    public enum UTF8: TextEncoding {
        public static var name: String { "UTF-8" }

        public static func decode(_ bytes: [UInt8], mode: DecodingErrorMode) throws(ViceroyError) -> String {
            if mode == .replacement {
                if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
                    return String(decoding: bytes[3...], as: Swift.UTF8.self)
                }
                return String(decoding: bytes, as: Swift.UTF8.self)
            }
            return try runDecode(UTF8Decoder(), bytes, mode, stripBOM: true)
        }

        public static func encode(_ string: String, mode: EncodingErrorMode) throws(ViceroyError) -> [UInt8] {
            Array(string.utf8)   // a String already *is* UTF-8
        }
    }
}
