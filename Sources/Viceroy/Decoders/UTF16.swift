//===----------------------------------------------------------------------===//
// Viceroy — UTF-16LE / UTF-16BE  (WHATWG shared "UTF-16 decoder")
//===----------------------------------------------------------------------===//

@usableFromInline
struct UTF16Decoder: ByteHandler {
    @usableFromInline let bigEndian: Bool
    @usableFromInline var leadByte: UInt16 = 0xFFFF   // 0xFFFF sentinel = "none"
    @usableFromInline var leadSurrogate: UInt32 = 0    // 0 = none (a surrogate is never 0)

    @inlinable init(bigEndian: Bool) { self.bigEndian = bigEndian }

    @inlinable
    mutating func handle(_ byte: UInt8) -> ByteResult {
        if leadByte == 0xFFFF {
            leadByte = UInt16(byte)
            return .again
        }
        let unit: UInt32 = bigEndian
            ? (UInt32(leadByte) << 8) | UInt32(byte)
            : (UInt32(byte) << 8) | UInt32(leadByte)
        leadByte = 0xFFFF

        if leadSurrogate != 0 {
            let lead = leadSurrogate
            leadSurrogate = 0
            if unit >= 0xDC00 && unit <= 0xDFFF {
                let cp = 0x10000 + ((lead - 0xD800) << 10) + (unit - 0xDC00)
                return .scalar(Unicode.Scalar(cp)!)
            }
            // Orphaned lead surrogate: emit error, reprocess these two bytes.
            return .errorPrepend(serialize(UInt16(unit)))
        }
        if unit >= 0xD800 && unit <= 0xDBFF {
            leadSurrogate = unit
            return .again
        }
        if unit >= 0xDC00 && unit <= 0xDFFF {
            return .error   // lone trail surrogate
        }
        return .scalar(Unicode.Scalar(unit)!)
    }

    @inlinable
    mutating func handleEOF() -> ByteResult {
        if leadByte != 0xFFFF || leadSurrogate != 0 {
            leadByte = 0xFFFF; leadSurrogate = 0
            return .error
        }
        return .again
    }

    @usableFromInline @inline(__always)
    func serialize(_ unit: UInt16) -> ContiguousArray<UInt8> {
        bigEndian ? [UInt8(unit >> 8), UInt8(unit & 0xFF)]
                  : [UInt8(unit & 0xFF), UInt8(unit >> 8)]
    }
}

@usableFromInline
struct UTF16Encoder: ScalarHandler {
    @usableFromInline let bigEndian: Bool
    @inlinable init(bigEndian: Bool) { self.bigEndian = bigEndian }

    @usableFromInline @inline(__always)
    func emit(_ unit: UInt16, into out: inout [UInt8]) {
        if bigEndian { out.append(UInt8(unit >> 8)); out.append(UInt8(unit & 0xFF)) }
        else { out.append(UInt8(unit & 0xFF)); out.append(UInt8(unit >> 8)) }
    }

    @inlinable
    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult {
        let v = scalar.value
        if v <= 0xFFFF {
            emit(UInt16(v), into: &out)
        } else {
            let c = v - 0x10000
            emit(UInt16(0xD800 + (c >> 10)), into: &out)
            emit(UInt16(0xDC00 + (c & 0x3FF)), into: &out)
        }
        return .ok
    }
}

// MARK: - Static entry point

extension Encoding {
    /// UTF-16LE, resolved statically — links only this encoding's decoder and tables.
    public enum UTF16LE: TextEncoding {
        public static var name: String { "UTF-16LE" }

        public static func decode(_ bytes: [UInt8], mode: DecodingErrorMode) throws(ViceroyError) -> String {
            try runDecode(UTF16Decoder(bigEndian: false), bytes, mode, stripBOM: true)
        }

        public static func encode(_ string: String, mode: EncodingErrorMode) throws(ViceroyError) -> [UInt8] {
            try runEncode(UTF16Encoder(bigEndian: false), string.unicodeScalars, mode)
        }
    }
}

// MARK: - Static entry point

extension Encoding {
    /// UTF-16BE, resolved statically — links only this encoding's decoder and tables.
    public enum UTF16BE: TextEncoding {
        public static var name: String { "UTF-16BE" }

        public static func decode(_ bytes: [UInt8], mode: DecodingErrorMode) throws(ViceroyError) -> String {
            try runDecode(UTF16Decoder(bigEndian: true), bytes, mode, stripBOM: true)
        }

        public static func encode(_ string: String, mode: EncodingErrorMode) throws(ViceroyError) -> [UInt8] {
            try runEncode(UTF16Encoder(bigEndian: true), string.unicodeScalars, mode)
        }
    }
}
