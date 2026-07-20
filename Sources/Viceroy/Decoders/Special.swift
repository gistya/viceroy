//===----------------------------------------------------------------------===//
// Viceroy — Special decoders: "replacement" and "x-user-defined"
//===----------------------------------------------------------------------===//

/// WHATWG "replacement": any non-empty input decodes to a single U+FFFD, then
/// finishes. A security measure — dangerous labels (`hz-gb-2312`, `csiso2022kr`,
/// …) map here so hostile bytes can never be interpreted.
@usableFromInline
struct ReplacementDecoder: ByteHandler {
    @usableFromInline var reported = false
    @inlinable init() {}

    @inlinable
    mutating func handle(_ byte: UInt8) -> ByteResult {
        if reported { return .again }
        reported = true
        return .error
    }
    @inlinable mutating func handleEOF() -> ByteResult { .again }
}

/// WHATWG "x-user-defined": 0x00…0x7F → same code point; 0x80…0xFF → U+F780…U+F7FF.
@usableFromInline
struct XUserDefinedDecoder: ByteHandler {
    @inlinable init() {}

    @inlinable
    mutating func handle(_ byte: UInt8) -> ByteResult {
        if byte < 0x80 { return .scalar(Unicode.Scalar(byte)) }
        return .scalar(Unicode.Scalar(0xF780 + UInt32(byte) - 0x80)!)
    }
    @inlinable mutating func handleEOF() -> ByteResult { .again }
}

@usableFromInline
struct XUserDefinedEncoder: ScalarHandler {
    @inlinable init() {}

    @inlinable
    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult {
        let v = scalar.value
        if v <= 0x7F { out.append(UInt8(v)); return .ok }
        if v >= 0xF780 && v <= 0xF7FF { out.append(UInt8(v - 0xF780 + 0x80)); return .ok }
        return .unmappable
    }
}

// MARK: - Static entry point

extension Encoding {
    /// x-user-defined, resolved statically — links only this encoding's decoder and tables.
    public enum XUserDefined: TextEncoding {
        public static var name: String { "x-user-defined" }

        public static func decode(_ bytes: [UInt8], mode: DecodingErrorMode) throws(ViceroyError) -> String {
            try runDecode(XUserDefinedDecoder(), bytes, mode, stripBOM: false)
        }

        public static func encode(_ string: String, mode: EncodingErrorMode) throws(ViceroyError) -> [UInt8] {
            try runEncode(XUserDefinedEncoder(), string.unicodeScalars, mode)
        }
    }
}

// MARK: - Static entry point

extension Encoding {
    /// replacement, resolved statically — links only this encoding's decoder and tables.
    public enum Replacement: TextEncoding {
        public static var name: String { "replacement" }

        public static func decode(_ bytes: [UInt8], mode: DecodingErrorMode) throws(ViceroyError) -> String {
            try runDecode(ReplacementDecoder(), bytes, mode, stripBOM: false)
        }

        public static func encode(_ string: String, mode: EncodingErrorMode) throws(ViceroyError) -> [UInt8] {
            try runEncode(UTF8Encoder(), string.unicodeScalars, mode)
        }
    }
}
