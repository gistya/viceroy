//===----------------------------------------------------------------------===//
// Viceroy — EUC-JP  (WHATWG §12.1) — JIS X 0208 + 0212 + half-width katakana.
//===----------------------------------------------------------------------===//

struct EUCJPDecoder: ByteHandler {
    var jis0212flag = false
    var lead: UInt8 = 0

    mutating func handle(_ byte: UInt8) -> ByteResult {
        if lead == 0x8E && byte >= 0xA1 && byte <= 0xDF {
            lead = 0
            return .scalar(Unicode.Scalar(0xFF61 - 0xA1 + UInt32(byte))!)
        }
        if lead == 0x8F && byte >= 0xA1 && byte <= 0xFE {
            jis0212flag = true; lead = byte; return .again
        }
        if lead != 0 {
            let leading = Int(lead); lead = 0
            var codePoint: UInt16? = nil
            if leading >= 0xA1 && leading <= 0xFE && byte >= 0xA1 && byte <= 0xFE {
                let p = (leading - 0xA1) * 94 + Int(byte) - 0xA1
                let table = jis0212flag ? jis0212 : jis0208
                if p >= 0 && p < table.count, table[p] != 0xFFFF { codePoint = table[p] }
            }
            jis0212flag = false
            if let cp = codePoint { return .scalar(Unicode.Scalar(UInt32(cp))!) }
            if byte < 0x80 { return .errorPrepend([byte]) }
            return .error
        }
        if byte < 0x80 { return .scalar(Unicode.Scalar(byte)) }
        if byte == 0x8E || byte == 0x8F || (byte >= 0xA1 && byte <= 0xFE) {
            lead = byte; return .again
        }
        return .error
    }

    mutating func handleEOF() -> ByteResult {
        if lead != 0 { lead = 0; return .error }
        return .again
    }
}

struct EUCJPEncoder: ScalarHandler {
    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult {
        var v = scalar.value
        if v <= 0x7F { out.append(UInt8(v)); return .ok }
        if v == 0xA5 { out.append(0x5C); return .ok }                           // ¥
        if v == 0x203E { out.append(0x7E); return .ok }                         // ‾
        if v >= 0xFF61 && v <= 0xFF9F {                                         // half-width katakana
            out.append(0x8E); out.append(UInt8(v - 0xFF61 + 0xA1)); return .ok
        }
        if v == 0x2212 { v = 0xFF0D }
        guard let p = jis0208Reverse[v] else { return .unmappable }
        out.append(UInt8(p / 94 + 0xA1))
        out.append(UInt8(p % 94 + 0xA1))
        return .ok
    }
}
