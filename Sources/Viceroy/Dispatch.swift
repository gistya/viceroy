//===----------------------------------------------------------------------===//
// Viceroy — Public whole-buffer API + scheme dispatch
//===----------------------------------------------------------------------===//

// MARK: - Public whole-buffer API (the 90% case)

extension Encoding {
    /// Decode `bytes` to a `String`. Malformed input is handled per `mode`
    /// (`.replacement` emits U+FFFD and resynchronizes; `.fatal` throws).
    /// A leading BOM is stripped for UTF-8/UTF-16 per WHATWG.
    @inlinable
    public func decode(_ bytes: [UInt8], mode: DecodingErrorMode = .replacement) throws(ViceroyError) -> String {
        try _decode(scheme, bytes, mode)
    }

    /// Decode `bytes` to an array of Unicode scalars.
    @inlinable
    public func decodeScalars(_ bytes: [UInt8], mode: DecodingErrorMode = .replacement) throws(ViceroyError) -> [Unicode.Scalar] {
        Array(try _decode(scheme, bytes, mode).unicodeScalars)
    }

    /// Encode a `String` to bytes. Unrepresentable scalars are handled per `mode`.
    @inlinable
    public func encode(_ string: String, mode: EncodingErrorMode = .fatal) throws(ViceroyError) -> [UInt8] {
        // Fast path: a String already *is* UTF-8; every scalar is representable.
        if case .utf8 = scheme { return Array(string.utf8) }
        return try encodeScalars(string.unicodeScalars, mode: mode)
    }

    /// Encode a scalar sequence to bytes.
    @inlinable
    public func encodeScalars(
        _ scalars: some Sequence<Unicode.Scalar>,
        mode: EncodingErrorMode = .fatal
    ) throws(ViceroyError) -> [UInt8] {
        try _encode(scheme, scalars, mode)
    }

}

// NOTE: `runDecode`/`runEncode` deliberately live in Runner.swift — see the note
// there. Keeping them out of this file is what lets the per-encoding static
// entry points avoid linking the all-encodings switch below.

// MARK: - Decode dispatch

@usableFromInline
func _decode(_ scheme: Scheme, _ bytes: [UInt8], _ mode: DecodingErrorMode) throws(ViceroyError) -> String {
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
#if SingleByte
    case .singleByte(let i): return try runDecode(SingleByteDecoder(tableIndex: i), bytes, mode, stripBOM: false)
#else
    case .singleByte:      throw unavailable("SingleByte")
#endif
    case .replacement:     return try runDecode(ReplacementDecoder(), bytes, mode, stripBOM: false)
    case .xUserDefined:    return try runDecode(XUserDefinedDecoder(), bytes, mode, stripBOM: false)
#if Japanese
    case .shiftJIS:        return try runDecode(ShiftJISDecoder(), bytes, mode, stripBOM: false)
    case .eucJP:           return try runDecode(EUCJPDecoder(), bytes, mode, stripBOM: false)
    case .iso2022JP:       return try runDecode(ISO2022JPDecoder(), bytes, mode, stripBOM: false)
#else
    case .shiftJIS, .eucJP, .iso2022JP: throw unavailable("Japanese")
#endif
#if Chinese
    case .big5:            return try runDecode(Big5Decoder(), bytes, mode, stripBOM: false)
    case .gbk, .gb18030:   return try runDecode(GB18030Decoder(), bytes, mode, stripBOM: false)
#else
    case .big5, .gbk, .gb18030: throw unavailable("Chinese")
#endif
#if Korean
    case .eucKR:           return try runDecode(EUCKRDecoder(), bytes, mode, stripBOM: false)
#else
    case .eucKR:           throw unavailable("Korean")
#endif
    }
}

// MARK: - Encode dispatch

@usableFromInline
func _encode(_ scheme: Scheme, _ scalars: some Sequence<Unicode.Scalar>, _ mode: EncodingErrorMode) throws(ViceroyError) -> [UInt8] {
    switch scheme {
    case .utf8, .replacement:
        return try runEncode(UTF8Encoder(), scalars, mode)
    case .utf16le:         return try runEncode(UTF16Encoder(bigEndian: false), scalars, mode)
    case .utf16be:         return try runEncode(UTF16Encoder(bigEndian: true), scalars, mode)
#if SingleByte
    case .singleByte(let i): return try runEncode(SingleByteEncoder(tableIndex: i), scalars, mode)
#else
    case .singleByte:      throw unavailable("SingleByte")
#endif
    case .xUserDefined:    return try runEncode(XUserDefinedEncoder(), scalars, mode)
#if Japanese
    case .shiftJIS:        return try runEncode(ShiftJISEncoder(), scalars, mode)
    case .eucJP:           return try runEncode(EUCJPEncoder(), scalars, mode)
    case .iso2022JP:       return try runEncode(ISO2022JPEncoder(), scalars, mode)
#else
    case .shiftJIS, .eucJP, .iso2022JP: throw unavailable("Japanese")
#endif
#if Chinese
    case .big5:            return try runEncode(Big5Encoder(), scalars, mode)
    case .gbk:             return try runEncode(GB18030Encoder(gb18030: false), scalars, mode)
    case .gb18030:         return try runEncode(GB18030Encoder(gb18030: true), scalars, mode)
#else
    case .big5, .gbk, .gb18030: throw unavailable("Chinese")
#endif
#if Korean
    case .eucKR:           return try runEncode(EUCKREncoder(), scalars, mode)
#else
    case .eucKR:           throw unavailable("Korean")
#endif
    }
}


/// Error for an encoding whose family was excluded at build time.
@usableFromInline
func unavailable(_ trait: String) -> ViceroyError {
    ViceroyError(code: .encodingUnavailable, offset: 0,
                 message: "encoding family excluded at build time; enable the \"\(trait)\" package trait")
}
