//===----------------------------------------------------------------------===//
// Viceroy — Core
//
// The engine every decoder and encoder plugs into. It models the WHATWG
// Encoding Standard's "run an encoding's decoder/encoder over an I/O queue"
// exactly: a decoder is a *stateful, byte-at-a-time handler*; an encoder is a
// *stateful, scalar-at-a-time handler*. Because all partial state lives inside
// the handler (a pending lead byte, an ISO-2022-JP charset, …) — never in a
// side buffer — feeding the same bytes as one buffer or as arbitrarily split
// chunks produces identical output. Streaming ≡ whole-buffer, by construction.
//===----------------------------------------------------------------------===//

// MARK: - Error reporting

/// A failure raised in `.fatal` decode mode or by a `.fatal` encoder, carrying
/// the byte offset (decode) / scalar offset (encode) of the offending unit.
public struct ViceroyError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Code: Sendable, Equatable {
        /// A byte sequence could not be decoded in `.fatal` mode.
        case invalidByteSequence
        /// A scalar could not be encoded in `.fatal` mode.
        case unmappableScalar
    }
    public var code: Code
    /// Byte offset (decoding) or scalar offset (encoding) at which the error occurred.
    public var offset: Int
    public var message: String

    @inlinable
    public init(code: Code, offset: Int, message: String) {
        self.code = code
        self.offset = offset
        self.message = message
    }

    public var description: String { "ViceroyError(\(code), offset: \(offset)): \(message)" }
}

// MARK: - Error modes

/// How the decoder treats bytes that do not form a valid sequence.
public enum DecodingErrorMode: Sendable, Equatable {
    /// Emit U+FFFD (REPLACEMENT CHARACTER) and resynchronize per the WHATWG spec.
    case replacement
    /// Throw `ViceroyError` at the first malformed unit.
    case fatal
}

/// How the encoder treats scalars the target encoding cannot represent.
public enum EncodingErrorMode: Sendable, Equatable {
    /// Emit a fixed replacement byte (WHATWG uses `0x3F`, `?`, for form submission).
    case replacement(UInt8)
    /// Throw `ViceroyError` at the first unmappable scalar.
    case fatal
    /// Emit an HTML decimal numeric character reference, e.g. `&#1234;` — the
    /// WHATWG "html" error mode used by `<form>` submission.
    case htmlNumericEscape
    /// Silently drop the scalar (the iconv `//IGNORE` behavior).
    case drop
}

extension EncodingErrorMode {
    /// The conventional `?` replacement byte.
    public static var questionMark: EncodingErrorMode { .replacement(0x3F) }
}

// MARK: - Decoder handler protocol

/// One step's worth of decoder output.
@usableFromInline
enum ByteResult {
    /// Emit a single scalar.
    case scalar(Unicode.Scalar)
    /// Emit two scalars (Big5 has a handful of these).
    case pair(Unicode.Scalar, Unicode.Scalar)
    /// The byte was absorbed into pending state; emit nothing.
    case again
    /// The byte(s) are malformed. Emit U+FFFD / throw. No reprocessing.
    case error
    /// Malformed: emit one error marker, then reprocess `bytes` (WHATWG "prepend
    /// to stream" — e.g. gb18030 restores three consumed bytes on a bad 4-byte run).
    case errorPrepend(ContiguousArray<UInt8>)
}

/// A stateful, byte-at-a-time decoder. All partial-sequence state is held in
/// `self`, which is what makes chunked and whole-buffer decoding identical.
@usableFromInline
protocol ByteHandler {
    /// Consume one input byte.
    mutating func handle(_ byte: UInt8) -> ByteResult
    /// Signal end of input. `.again` means a clean finish; `.error` means a
    /// truncated sequence was pending (e.g. a lead byte with no trail).
    mutating func handleEOF() -> ByteResult
}

// MARK: - Encoder handler protocol

/// One step's worth of encoder output.
@usableFromInline
enum EncodeResult {
    /// Bytes were appended to the sink.
    case ok
    /// Bytes were appended (e.g. an ISO-2022-JP charset-switch escape), and the
    /// *same* scalar must be re-encoded now in the new state.
    case retry
    /// The scalar cannot be represented; the driver applies `EncodingErrorMode`.
    case unmappable
}

/// A stateful, scalar-at-a-time encoder.
@usableFromInline
protocol ScalarHandler {
    /// Encode one scalar, appending its bytes to `out`.
    mutating func encode(_ scalar: Unicode.Scalar, into out: inout [UInt8]) -> EncodeResult
    /// Flush trailing state at end of input (e.g. ISO-2022-JP returns to ASCII).
    mutating func finish(into out: inout [UInt8])
}

extension ScalarHandler {
    @inlinable
    mutating func finish(into out: inout [UInt8]) {}
}

// MARK: - Scalar sink

/// Where decoded scalars go. Whole-buffer decoding targets a UTF-8 `[UInt8]`
/// accumulator (one `String` build at the end — far cheaper than per-scalar
/// `UnicodeScalarView.append`); streaming targets the caller's scalar view.
@usableFromInline
protocol ScalarSink {
    mutating func emit(_ scalar: Unicode.Scalar)
    mutating func emitReplacement()   // U+FFFD
}

/// Append `scalar`'s UTF-8 encoding to `out`. `v` is always a valid scalar value.
@usableFromInline @inline(__always)
func appendUTF8(_ v: UInt32, _ out: inout [UInt8]) {
    switch v {
    case 0..<0x80:
        out.append(UInt8(v))
    case 0..<0x800:
        out.append(UInt8(0xC0 | (v >> 6)))
        out.append(UInt8(0x80 | (v & 0x3F)))
    case 0..<0x10000:
        out.append(UInt8(0xE0 | (v >> 12)))
        out.append(UInt8(0x80 | ((v >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (v & 0x3F)))
    default:
        out.append(UInt8(0xF0 | (v >> 18)))
        out.append(UInt8(0x80 | ((v >> 12) & 0x3F)))
        out.append(UInt8(0x80 | ((v >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (v & 0x3F)))
    }
}

extension Array: ScalarSink where Element == UInt8 {
    @usableFromInline @inline(__always) mutating func emit(_ scalar: Unicode.Scalar) { appendUTF8(scalar.value, &self) }
    @usableFromInline @inline(__always) mutating func emitReplacement() { append(0xEF); append(0xBF); append(0xBD) }
}

extension String.UnicodeScalarView: ScalarSink {
    @usableFromInline @inline(__always) mutating func emit(_ scalar: Unicode.Scalar) { append(scalar) }
    @usableFromInline @inline(__always) mutating func emitReplacement() { append("\u{FFFD}") }
}

// MARK: - Decode driver

/// Drives a `ByteHandler` over a byte sequence, honoring the error mode and the
/// WHATWG "prepend" reprocessing rule. Generic so each call site specializes and
/// devirtualizes the per-byte dispatch.
@usableFromInline
struct DecodeDriver<H: ByteHandler> {
    @usableFromInline var handler: H
    @usableFromInline var mode: DecodingErrorMode
    /// Absolute byte offset consumed so far (for `.fatal` error reporting).
    @usableFromInline var offset: Int = 0
    /// Bytes queued for reprocessing (WHATWG "prepend to stream"), FIFO.
    @usableFromInline var pushback: ContiguousArray<UInt8> = []

    @inlinable
    init(_ handler: H, mode: DecodingErrorMode) {
        self.handler = handler
        self.mode = mode
    }

    /// Feed one chunk of bytes, appending decoded scalars to `sink`.
    @inlinable
    mutating func feed<S: ScalarSink>(
        _ bytes: some Sequence<UInt8>,
        into sink: inout S
    ) throws {
        for b in bytes {
            try step(b, into: &sink)
            // Drain any bytes the handler asked to reprocess.
            while !pushback.isEmpty {
                let pb = pushback.removeFirst()
                try step(pb, into: &sink)
            }
        }
    }

    @inlinable
    mutating func step<S: ScalarSink>(_ byte: UInt8, into sink: inout S) throws {
        switch handler.handle(byte) {
        case .scalar(let s):
            sink.emit(s)
        case .pair(let a, let b):
            sink.emit(a); sink.emit(b)
        case .again:
            break
        case .error:
            try emitError(into: &sink)
        case .errorPrepend(let bytes):
            // Queue for reprocessing *after* the error marker, preserving order.
            pushback.insert(contentsOf: bytes, at: 0)
            try emitError(into: &sink)
        }
        offset &+= 1
    }

    /// Flush end-of-input state. A decoder may, at EOF, restore bytes for
    /// reprocessing (ISO-2022-JP re-emits the literal of a truncated escape),
    /// so this drains pushback through the normal `step` path and re-checks EOF
    /// until the stream is genuinely finished.
    @inlinable
    mutating func finish<S: ScalarSink>(into sink: inout S) throws {
        var guardCount = 0
        while true {
            while !pushback.isEmpty {
                let b = pushback.removeFirst()
                try step(b, into: &sink)
            }
            switch handler.handleEOF() {
            case .again:
                return
            case .scalar(let s):
                sink.emit(s)
            case .pair(let a, let b):
                sink.emit(a); sink.emit(b)
            case .error:
                try emitError(into: &sink)
                if pushback.isEmpty { return }
            case .errorPrepend(let bytes):
                pushback.insert(contentsOf: bytes, at: 0)
                try emitError(into: &sink)
            }
            guardCount += 1
            precondition(guardCount <= 16, "EOF drain did not converge")
        }
    }

    @inlinable
    mutating func emitError<S: ScalarSink>(into sink: inout S) throws {
        switch mode {
        case .replacement:
            sink.emitReplacement()
        case .fatal:
            throw ViceroyError(code: .invalidByteSequence, offset: offset,
                               message: "invalid byte sequence")
        }
    }
}

// MARK: - Encode driver

/// Drives a `ScalarHandler` over a scalar sequence, honoring `EncodingErrorMode`.
@usableFromInline
struct EncodeDriver<H: ScalarHandler> {
    @usableFromInline var handler: H
    @usableFromInline var mode: EncodingErrorMode
    @usableFromInline var offset: Int = 0

    @inlinable
    init(_ handler: H, mode: EncodingErrorMode) {
        self.handler = handler
        self.mode = mode
    }

    @inlinable
    mutating func feed(
        _ scalars: some Sequence<Unicode.Scalar>,
        into out: inout [UInt8]
    ) throws {
        for s in scalars {
            var guardCount = 0
            loop: while true {
                switch handler.encode(s, into: &out) {
                case .ok:
                    break loop
                case .retry:
                    guardCount += 1
                    precondition(guardCount <= 8, "encoder retry did not converge")
                    continue
                case .unmappable:
                    try emitUnmappable(s, into: &out)
                    break loop
                }
            }
            offset &+= 1
        }
    }

    @inlinable
    mutating func finish(into out: inout [UInt8]) {
        handler.finish(into: &out)
    }

    @inlinable
    mutating func emitUnmappable(_ s: Unicode.Scalar, into out: inout [UInt8]) throws {
        switch mode {
        case .replacement(let byte):
            out.append(byte)
        case .htmlNumericEscape:
            // "&#" <decimal> ";"  (all ASCII)
            out.append(0x26); out.append(0x23) // & #
            var n = s.value
            if n == 0 { out.append(0x30) } else {
                var digits: [UInt8] = []
                while n > 0 { digits.append(UInt8(0x30 + n % 10)); n /= 10 }
                out.append(contentsOf: digits.reversed())
            }
            out.append(0x3B) // ;
        case .drop:
            break
        case .fatal:
            throw ViceroyError(code: .unmappableScalar, offset: offset,
                               message: "scalar U+\(hexUpper(s.value)) cannot be encoded")
        }
    }
}

// MARK: - Small utilities

/// Uppercase hex without Foundation, for error messages.
@usableFromInline
func hexUpper(_ v: UInt32) -> String {
    if v == 0 { return "0" }
    let digits: [Character] = ["0","1","2","3","4","5","6","7","8","9","A","B","C","D","E","F"]
    var out: [Character] = []
    var n = v
    while n > 0 { out.append(digits[Int(n & 0xF)]); n >>= 4 }
    return String(out.reversed())
}
