//===----------------------------------------------------------------------===//
// Viceroy — Incremental / streaming API
//
// Feed input in arbitrarily-sized chunks; because every decoder/encoder keeps
// its partial state internally, the result is byte-for-byte identical to
// decoding the whole buffer at once — even when a multibyte sequence or an
// ISO-2022-JP escape is split across a chunk boundary.
//===----------------------------------------------------------------------===//

// MARK: - Type-erased driver boxes

@usableFromInline
class AnyDecoderBox {
    @usableFromInline init() {}
    @usableFromInline func feed(_ bytes: [UInt8], into sink: inout String.UnicodeScalarView) throws { fatalError() }
    @usableFromInline func finish(into sink: inout String.UnicodeScalarView) throws { fatalError() }
}

@usableFromInline
final class DecoderBox<H: ByteHandler>: AnyDecoderBox {
    @usableFromInline var driver: DecodeDriver<H>
    @usableFromInline init(_ h: H, _ mode: DecodingErrorMode) { driver = DecodeDriver(h, mode: mode) }
    @usableFromInline override func feed(_ bytes: [UInt8], into sink: inout String.UnicodeScalarView) throws {
        try driver.feed(bytes, into: &sink)
    }
    @usableFromInline override func finish(into sink: inout String.UnicodeScalarView) throws {
        try driver.finish(into: &sink)
    }
}

@usableFromInline
class AnyEncoderBox {
    @usableFromInline init() {}
    @usableFromInline func feed(_ scalars: [Unicode.Scalar], into out: inout [UInt8]) throws { fatalError() }
    @usableFromInline func finish(into out: inout [UInt8]) { fatalError() }
}

@usableFromInline
final class EncoderBox<H: ScalarHandler>: AnyEncoderBox {
    @usableFromInline var driver: EncodeDriver<H>
    @usableFromInline init(_ h: H, _ mode: EncodingErrorMode) { driver = EncodeDriver(h, mode: mode) }
    @usableFromInline override func feed(_ scalars: [Unicode.Scalar], into out: inout [UInt8]) throws {
        try driver.feed(scalars, into: &out)
    }
    @usableFromInline override func finish(into out: inout [UInt8]) { driver.finish(into: &out) }
}

func makeDecoderBox(_ scheme: Scheme, _ mode: DecodingErrorMode) -> AnyDecoderBox {
    switch scheme {
    case .utf8:              return DecoderBox(UTF8Decoder(), mode)
    case .utf16le:           return DecoderBox(UTF16Decoder(bigEndian: false), mode)
    case .utf16be:           return DecoderBox(UTF16Decoder(bigEndian: true), mode)
    case .singleByte(let i): return DecoderBox(SingleByteDecoder(tableIndex: i), mode)
    case .replacement:       return DecoderBox(ReplacementDecoder(), mode)
    case .xUserDefined:      return DecoderBox(XUserDefinedDecoder(), mode)
    case .shiftJIS:          return DecoderBox(ShiftJISDecoder(), mode)
    case .eucJP:             return DecoderBox(EUCJPDecoder(), mode)
    case .iso2022JP:         return DecoderBox(ISO2022JPDecoder(), mode)
    case .big5:              return DecoderBox(Big5Decoder(), mode)
    case .gbk, .gb18030:     return DecoderBox(GB18030Decoder(), mode)
    case .eucKR:             return DecoderBox(EUCKRDecoder(), mode)
    }
}

func makeEncoderBox(_ scheme: Scheme, _ mode: EncodingErrorMode) -> AnyEncoderBox {
    switch scheme {
    case .utf8, .replacement: return EncoderBox(UTF8Encoder(), mode)
    case .utf16le:            return EncoderBox(UTF16Encoder(bigEndian: false), mode)
    case .utf16be:            return EncoderBox(UTF16Encoder(bigEndian: true), mode)
    case .singleByte(let i):  return EncoderBox(SingleByteEncoder(tableIndex: i), mode)
    case .xUserDefined:       return EncoderBox(XUserDefinedEncoder(), mode)
    case .shiftJIS:           return EncoderBox(ShiftJISEncoder(), mode)
    case .eucJP:              return EncoderBox(EUCJPEncoder(), mode)
    case .iso2022JP:          return EncoderBox(ISO2022JPEncoder(), mode)
    case .big5:               return EncoderBox(Big5Encoder(), mode)
    case .gbk:                return EncoderBox(GB18030Encoder(gb18030: false), mode)
    case .gb18030:            return EncoderBox(GB18030Encoder(gb18030: true), mode)
    case .eucKR:              return EncoderBox(EUCKREncoder(), mode)
    }
}

// MARK: - Public streaming decoder

/// Decodes a stream of bytes chunk by chunk. Strips a leading BOM for UTF-8/16
/// (even one split across chunk boundaries), matching whole-buffer `decode`.
///
/// Not `Sendable` — a streaming decoder is single-owner, stateful I/O state.
public struct StreamingDecoder {
    private let box: AnyDecoderBox
    private let expectedBOM: [UInt8]?
    private var bomBuffer: [UInt8] = []
    private var bomResolved: Bool

    public init(_ encoding: Encoding, mode: DecodingErrorMode = .replacement) {
        box = makeDecoderBox(encoding.scheme, mode)
        switch encoding.scheme {
        case .utf8:    expectedBOM = [0xEF, 0xBB, 0xBF]
        case .utf16le: expectedBOM = [0xFF, 0xFE]
        case .utf16be: expectedBOM = [0xFE, 0xFF]
        default:       expectedBOM = nil
        }
        bomResolved = (expectedBOM == nil)
    }

    /// Feed one chunk, appending decoded scalars to `sink`. Throws in `.fatal`
    /// mode on the first malformed unit.
    public mutating func decode(
        _ chunk: some Sequence<UInt8>, into sink: inout String.UnicodeScalarView
    ) throws {
        if bomResolved {
            try box.feed(Array(chunk), into: &sink)
            return
        }
        bomBuffer.append(contentsOf: chunk)
        try resolveBOM(flush: false, into: &sink)
    }

    /// Flush trailing state at end of input.
    public mutating func finish(into sink: inout String.UnicodeScalarView) throws {
        try resolveBOM(flush: true, into: &sink)
        try box.finish(into: &sink)
    }

    private mutating func resolveBOM(flush: Bool, into sink: inout String.UnicodeScalarView) throws {
        guard let bom = expectedBOM, !bomResolved else { return }
        let n = min(bomBuffer.count, bom.count)
        for i in 0..<n where bomBuffer[i] != bom[i] {
            bomResolved = true
            let buf = bomBuffer; bomBuffer = []
            try box.feed(buf, into: &sink)
            return
        }
        if bomBuffer.count >= bom.count {
            bomResolved = true
            let rest = Array(bomBuffer[bom.count...]); bomBuffer = []
            try box.feed(rest, into: &sink)
        } else if flush {
            // Stream ended inside a partial (non-)BOM; it wasn't a full BOM.
            bomResolved = true
            let buf = bomBuffer; bomBuffer = []
            try box.feed(buf, into: &sink)
        }
    }
}

// MARK: - Public streaming encoder

/// Encodes a stream of scalars chunk by chunk. `finish` flushes trailing state
/// (e.g. ISO-2022-JP's return-to-ASCII escape).
public struct StreamingEncoder {
    private let box: AnyEncoderBox

    public init(_ encoding: Encoding, mode: EncodingErrorMode = .fatal) {
        box = makeEncoderBox(encoding.scheme, mode)
    }

    public mutating func encode(
        _ scalars: some Sequence<Unicode.Scalar>, into out: inout [UInt8]
    ) throws {
        try box.feed(Array(scalars), into: &out)
    }

    public mutating func finish(into out: inout [UInt8]) { box.finish(into: &out) }
}
