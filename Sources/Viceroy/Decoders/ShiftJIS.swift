#if Japanese
//===----------------------------------------------------------------------===//
// Viceroy — Shift_JIS  (WHATWG §12.3)
//===----------------------------------------------------------------------===//

struct ShiftJISDecoder: ByteHandler {
    var lead: UInt8 = 0

    mutating func handle(_ byte: UInt8) -> ByteResult {
        if lead != 0 {
            let leading = Int(lead); lead = 0
            let offset = byte < 0x7F ? 0x40 : 0x41
            let leadingOffset = leading < 0xA0 ? 0x81 : 0xC1
            var pointer: Int? = nil
            if (byte >= 0x40 && byte <= 0x7E) || (byte >= 0x80 && byte <= 0xFC) {
                pointer = (leading - leadingOffset) * 188 + Int(byte) - offset
            }
            if let p = pointer, p >= 8836 && p <= 10715 {
                // EUDC (Windows private-use legacy).
                return .scalar(Unicode.Scalar(UInt32(0xE000 - 8836 + p))!)
            }
            if let p = pointer, p >= 0 && p < jis0208.count, jis0208[p] != 0xFFFF {
                return .scalar(Unicode.Scalar(UInt32(jis0208[p]))!)
            }
            if byte < 0x80 { return .errorPrepend([byte]) }
            return .error
        }
        if byte <= 0x80 { return .scalar(Unicode.Scalar(byte)) }               // ASCII or 0x80
        if byte >= 0xA1 && byte <= 0xDF {                                       // half-width katakana
            return .scalar(Unicode.Scalar(0xFF61 - 0xA1 + UInt32(byte))!)
        }
        if (byte >= 0x81 && byte <= 0x9F) || (byte >= 0xE0 && byte <= 0xFC) {
            lead = byte; return .again
        }
        return .error
    }

    mutating func handleEOF() -> ByteResult {
        if lead != 0 { lead = 0; return .error }
        return .again
    }
}

struct ShiftJISEncoder: ScalarHandler {
    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult {
        var v = scalar.value
        if v <= 0x80 { out.append(UInt8(v)); return .ok }                       // ASCII or U+0080
        if v == 0xA5 { out.append(0x5C); return .ok }                           // ¥
        if v == 0x203E { out.append(0x7E); return .ok }                         // ‾
        if v >= 0xFF61 && v <= 0xFF9F { out.append(UInt8(v - 0xFF61 + 0xA1)); return .ok }
        if v == 0x2212 { v = 0xFF0D }                                           // − → －
        guard let p = shiftJISReverse[v] else { return .unmappable }
        let leading = p / 188
        let leadingOffset = leading < 0x1F ? 0x81 : 0xC1
        let trailing = p % 188
        let offset = trailing < 0x3F ? 0x40 : 0x41
        out.append(UInt8(leading + leadingOffset))
        out.append(UInt8(trailing + offset))
        return .ok
    }
}

// MARK: - Static entry point

extension Encoding {
    /// Shift_JIS, resolved statically. Links only this decoder + the jis0208 table.
    public enum ShiftJIS: TextEncoding {
        public static var name: String { "Shift_JIS" }

        public static func decode(_ bytes: [UInt8], mode: DecodingErrorMode) throws(ViceroyError) -> String {
            try runDecode(ShiftJISDecoder(), bytes, mode, stripBOM: false)
        }

        public static func encode(_ string: String, mode: EncodingErrorMode) throws(ViceroyError) -> [UInt8] {
            try runEncode(ShiftJISEncoder(), string.unicodeScalars, mode)
        }
    }
}
#endif
