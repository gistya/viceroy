//===----------------------------------------------------------------------===//
// Viceroy — Big5  (WHATWG §11.1) — note the four two-scalar pointers.
//===----------------------------------------------------------------------===//

struct Big5Decoder: ByteHandler {
    var lead: UInt8 = 0

    mutating func handle(_ byte: UInt8) -> ByteResult {
        if lead != 0 {
            let leading = Int(lead); lead = 0
            let offset = byte < 0x7F ? 0x40 : 0x62
            var pointer: Int? = nil
            if (byte >= 0x40 && byte <= 0x7E) || (byte >= 0xA1 && byte <= 0xFE) {
                pointer = (leading - 0x81) * 157 + (Int(byte) - offset)
            }
            if let p = pointer {
                // Indexes hold single code points, so these four decode to a pair.
                switch p {
                case 1133: return .pair("\u{00CA}", "\u{0304}")
                case 1135: return .pair("\u{00CA}", "\u{030C}")
                case 1164: return .pair("\u{00EA}", "\u{0304}")
                case 1166: return .pair("\u{00EA}", "\u{030C}")
                default: break
                }
                if p >= 0 && p < big5Index.count, big5Index[p] != 0xFFFF_FFFF {
                    return .scalar(Unicode.Scalar(big5Index[p])!)
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

struct Big5Encoder: ScalarHandler {
    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult {
        let v = scalar.value
        if v <= 0x7F { out.append(UInt8(v)); return .ok }
        guard let p = big5Reverse[v] else { return .unmappable }
        let leading = p / 157 + 0x81
        let trailing = p % 157
        let offset = trailing < 0x3F ? 0x40 : 0x62
        out.append(UInt8(leading))
        out.append(UInt8(trailing + offset))
        return .ok
    }
}
