//===----------------------------------------------------------------------===//
// Viceroy — gb18030 / GBK  (WHATWG §10.2)
//
// Shared decoder (GBK's decoder *is* gb18030's). The encoder differs by one
// boolean: GBK stops at two bytes (U+20AC → 0x80), while gb18030 can encode all
// of Unicode via the algorithmic four-byte ranges.
//===----------------------------------------------------------------------===//

struct GB18030Decoder: ByteHandler {
    var first: UInt8 = 0, second: UInt8 = 0, third: UInt8 = 0

    mutating func handle(_ byte: UInt8) -> ByteResult {
        if third != 0 {
            if byte < 0x30 || byte > 0x39 {
                let s2 = second, s3 = third
                first = 0; second = 0; third = 0
                return .errorPrepend([s2, s3, byte])
            }
            let pointer = (UInt32(first) - 0x81) * (10 * 126 * 10)
                        + (UInt32(second) - 0x30) * (10 * 126)
                        + (UInt32(third) - 0x81) * 10
                        + UInt32(byte) - 0x30
            first = 0; second = 0; third = 0
            guard let cp = gb18030RangesCodePoint(pointer) else { return .error }
            return .scalar(Unicode.Scalar(cp)!)
        }
        if second != 0 {
            if byte >= 0x81 && byte <= 0xFE { third = byte; return .again }
            let s2 = second
            first = 0; second = 0
            return .errorPrepend([s2, byte])
        }
        if first != 0 {
            if byte >= 0x30 && byte <= 0x39 { second = byte; return .again }
            let leading = Int(first); first = 0
            let offset = byte < 0x7F ? 0x40 : 0x41
            var pointer: Int? = nil
            if (byte >= 0x40 && byte <= 0x7E) || (byte >= 0x80 && byte <= 0xFE) {
                pointer = (leading - 0x81) * 190 + (Int(byte) - offset)
            }
            if let p = pointer, p >= 0 && p < gb18030Index.count, gb18030Index[p] != 0xFFFF {
                return .scalar(Unicode.Scalar(UInt32(gb18030Index[p]))!)
            }
            if byte < 0x80 { return .errorPrepend([byte]) }
            return .error
        }
        if byte < 0x80 { return .scalar(Unicode.Scalar(byte)) }
        if byte == 0x80 { return .scalar(Unicode.Scalar(0x20AC)!) }             // €
        if byte >= 0x81 && byte <= 0xFE { first = byte; return .again }
        return .error
    }

    mutating func handleEOF() -> ByteResult {
        if first != 0 || second != 0 || third != 0 {
            first = 0; second = 0; third = 0
            return .error
        }
        return .again
    }
}

struct GB18030Encoder: ScalarHandler {
    /// `true` selects the GBK (two-byte-only) behavior.
    let isGBK: Bool
    init(gb18030: Bool) { self.isGBK = !gb18030 }

    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult {
        let v = scalar.value
        if v <= 0x7F { out.append(UInt8(v)); return .ok }
        if v == 0xE5E5 { return .unmappable }                                   // cannot round-trip
        if isGBK && v == 0x20AC { out.append(0x80); return .ok }
        if let bytes = gb18030EncoderSideTable[v] {
            out.append(bytes.0); out.append(bytes.1); return .ok
        }
        if let p = gb18030Reverse[v] {
            let leading = p / 190 + 0x81
            let trailing = p % 190
            let offset = trailing < 0x3F ? 0x40 : 0x41
            out.append(UInt8(leading))
            out.append(UInt8(trailing + offset))
            return .ok
        }
        if isGBK { return .unmappable }
        // gb18030 four-byte algorithmic path — encodes any remaining scalar.
        let pointer = gb18030RangesPointer(v)
        let byte1 = pointer / (10 * 126 * 10)
        var rem = pointer % (10 * 126 * 10)
        let byte2 = rem / (10 * 126)
        rem %= (10 * 126)
        let byte3 = rem / 10
        let byte4 = rem % 10
        out.append(UInt8(byte1 + 0x81))
        out.append(UInt8(byte2 + 0x30))
        out.append(UInt8(byte3 + 0x81))
        out.append(UInt8(byte4 + 0x30))
        return .ok
    }
}
