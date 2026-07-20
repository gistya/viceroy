#if Korean
//===----------------------------------------------------------------------===//
// Viceroy — EUC-KR  (WHATWG §13.1) — covers Wansung + UHC (cp949).
//===----------------------------------------------------------------------===//

struct EUCKRDecoder: ByteHandler {
    var lead: UInt8 = 0

    mutating func handle(_ byte: UInt8) -> ByteResult {
        if lead != 0 {
            let leading = Int(lead); lead = 0
            if byte >= 0x41 && byte <= 0xFE {
                let p = (leading - 0x81) * 190 + (Int(byte) - 0x41)
                if p >= 0 && p < eucKRIndex.count, eucKRIndex[p] != 0xFFFF {
                    return .scalar(Unicode.Scalar(UInt32(eucKRIndex[p]))!)
                }
            }
            if byte < 0x80 { return .errorPrepend([byte]) }
            return .error
        }
        if byte < 0x80 { return .scalar(Unicode.Scalar(byte)) }
        if byte >= 0x81 && byte <= 0xFE { lead = byte; return .again }
        return .error
    }

    mutating func handleEOF() -> ByteResult {
        if lead != 0 { lead = 0; return .error }
        return .again
    }
}

struct EUCKREncoder: ScalarHandler {
    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult {
        let v = scalar.value
        if v <= 0x7F { out.append(UInt8(v)); return .ok }
        guard let p = eucKRReverse[v] else { return .unmappable }
        out.append(UInt8(p / 190 + 0x81))
        out.append(UInt8(p % 190 + 0x41))
        return .ok
    }
}

// MARK: - Static entry point

extension Encoding {
    /// EUC-KR, resolved statically — links only this encoding's decoder and tables.
    public enum EUCKR: TextEncoding {
        public static var name: String { "EUC-KR" }

        public static func decode(_ bytes: [UInt8], mode: DecodingErrorMode) throws(ViceroyError) -> String {
            try runDecode(EUCKRDecoder(), bytes, mode, stripBOM: false)
        }

        public static func encode(_ string: String, mode: EncodingErrorMode) throws(ViceroyError) -> [UInt8] {
            try runEncode(EUCKREncoder(), string.unicodeScalars, mode)
        }
    }
}
#endif
