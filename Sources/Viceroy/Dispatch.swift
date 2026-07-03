//===----------------------------------------------------------------------===//
// Viceroy — Public whole-buffer API + scheme dispatch
//===----------------------------------------------------------------------===//

// MARK: - Public whole-buffer API (the 90% case)

extension Encoding {
    /// Decode `bytes` to a `String`. Malformed input is handled per `mode`
    /// (`.replacement` emits U+FFFD and resynchronizes; `.fatal` throws).
    /// A leading BOM is stripped for UTF-8/UTF-16 per WHATWG.
    @inlinable
    public func decode(_ bytes: [UInt8], mode: DecodingErrorMode = .replacement) throws -> String {
        try _decode(scheme, bytes, mode)
    }

    /// Decode `bytes` to an array of Unicode scalars.
    @inlinable
    public func decodeScalars(_ bytes: [UInt8], mode: DecodingErrorMode = .replacement) throws -> [Unicode.Scalar] {
        Array(try _decode(scheme, bytes, mode).unicodeScalars)
    }

    /// Encode a `String` to bytes. Unrepresentable scalars are handled per `mode`.
    @inlinable
    public func encode(_ string: String, mode: EncodingErrorMode = .fatal) throws -> [UInt8] {
        // Fast path: a String already *is* UTF-8; every scalar is representable.
        if case .utf8 = scheme { return Array(string.utf8) }
        return try encodeScalars(string.unicodeScalars, mode: mode)
    }

    /// Encode a scalar sequence to bytes.
    @inlinable
    public func encodeScalars(
        _ scalars: some Sequence<Unicode.Scalar>,
        mode: EncodingErrorMode = .fatal
    ) throws -> [UInt8] {
        try _encode(scheme, scalars, mode)
    }

}

// MARK: - Generic runners

@usableFromInline
func runDecode<H: ByteHandler>(
    _ handler: H, _ bytes: [UInt8], _ mode: DecodingErrorMode, stripBOM: Bool
) throws -> String {
    var driver = DecodeDriver(handler, mode: mode)
    var out = [UInt8]()
    out.reserveCapacity(bytes.count + bytes.count / 4)
    try driver.feed(bytes, into: &out)
    try driver.finish(into: &out)
    // A leading BOM decodes to U+FEFF → EF BB BF in the UTF-8 output; drop it.
    if stripBOM, out.count >= 3, out[0] == 0xEF, out[1] == 0xBB, out[2] == 0xBF {
        return String(decoding: out[3...], as: UTF8.self)
    }
    return String(decoding: out, as: UTF8.self)
}

@usableFromInline
func runEncode<H: ScalarHandler>(
    _ handler: H, _ scalars: some Sequence<Unicode.Scalar>, _ mode: EncodingErrorMode
) throws -> [UInt8] {
    var driver = EncodeDriver(handler, mode: mode)
    var out: [UInt8] = []
    out.reserveCapacity(scalars.underestimatedCount)
    try driver.feed(scalars, into: &out)
    driver.finish(into: &out)
    return out
}

// MARK: - Decode dispatch

@usableFromInline
func _decode(_ scheme: Scheme, _ bytes: [UInt8], _ mode: DecodingErrorMode) throws -> String {
    switch scheme {
    case .utf8:
        // Fast path: the stdlib's UTF-8 decoder performs the identical WHATWG
        // U+FFFD "maximal subpart" substitution (proven by
        // UTF8FastPathEquivalenceTests) at ~30× the state machine's throughput.
        if mode == .replacement {
            if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
                return String(decoding: bytes[3...], as: UTF8.self)
            }
            return String(decoding: bytes, as: UTF8.self)
        }
        return try runDecode(UTF8Decoder(), bytes, mode, stripBOM: true)
    case .utf16le:         return try runDecode(UTF16Decoder(bigEndian: false), bytes, mode, stripBOM: true)
    case .utf16be:         return try runDecode(UTF16Decoder(bigEndian: true), bytes, mode, stripBOM: true)
    case .singleByte(let i): return try runDecode(SingleByteDecoder(tableIndex: i), bytes, mode, stripBOM: false)
    case .replacement:     return try runDecode(ReplacementDecoder(), bytes, mode, stripBOM: false)
    case .xUserDefined:    return try runDecode(XUserDefinedDecoder(), bytes, mode, stripBOM: false)
    case .shiftJIS:        return try runDecode(ShiftJISDecoder(), bytes, mode, stripBOM: false)
    case .eucJP:           return try runDecode(EUCJPDecoder(), bytes, mode, stripBOM: false)
    case .iso2022JP:       return try runDecode(ISO2022JPDecoder(), bytes, mode, stripBOM: false)
    case .big5:            return try runDecode(Big5Decoder(), bytes, mode, stripBOM: false)
    case .gbk, .gb18030:   return try runDecode(GB18030Decoder(), bytes, mode, stripBOM: false)
    case .eucKR:           return try runDecode(EUCKRDecoder(), bytes, mode, stripBOM: false)
    }
}

// MARK: - Encode dispatch

@usableFromInline
func _encode(_ scheme: Scheme, _ scalars: some Sequence<Unicode.Scalar>, _ mode: EncodingErrorMode) throws -> [UInt8] {
    switch scheme {
    case .utf8, .replacement:
        return try runEncode(UTF8Encoder(), scalars, mode)
    case .utf16le:         return try runEncode(UTF16Encoder(bigEndian: false), scalars, mode)
    case .utf16be:         return try runEncode(UTF16Encoder(bigEndian: true), scalars, mode)
    case .singleByte(let i): return try runEncode(SingleByteEncoder(tableIndex: i), scalars, mode)
    case .xUserDefined:    return try runEncode(XUserDefinedEncoder(), scalars, mode)
    case .shiftJIS:        return try runEncode(ShiftJISEncoder(), scalars, mode)
    case .eucJP:           return try runEncode(EUCJPEncoder(), scalars, mode)
    case .iso2022JP:       return try runEncode(ISO2022JPEncoder(), scalars, mode)
    case .big5:            return try runEncode(Big5Encoder(), scalars, mode)
    case .gbk:             return try runEncode(GB18030Encoder(gb18030: false), scalars, mode)
    case .gb18030:         return try runEncode(GB18030Encoder(gb18030: true), scalars, mode)
    case .eucKR:           return try runEncode(EUCKREncoder(), scalars, mode)
    }
}
