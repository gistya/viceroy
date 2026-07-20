//===----------------------------------------------------------------------===//
// Viceroy — Transcoder: A → Unicode pivot → B  (the iconv analogue)
//===----------------------------------------------------------------------===//

/// Converts bytes from one encoding directly to another, decoding through the
/// Unicode pivot and re-encoding — exactly how iconv, encoding_rs, and Go's
/// `x/text` work, so we keep N decoders + N encoders instead of N² converters.
public struct Transcoder: Sendable {
    public let from: Encoding
    public let to: Encoding
    public var onDecodeError: DecodingErrorMode
    public var onEncodeError: EncodingErrorMode

    public init(
        from: Encoding, to: Encoding,
        onDecodeError: DecodingErrorMode = .replacement,
        onEncodeError: EncodingErrorMode = .fatal
    ) {
        self.from = from
        self.to = to
        self.onDecodeError = onDecodeError
        self.onEncodeError = onEncodeError
    }

    /// Transcode a whole buffer.
    public func transcode(_ bytes: [UInt8]) throws(ViceroyError) -> [UInt8] {
        let scalars = try from.decode(bytes, mode: onDecodeError).unicodeScalars
        return try to.encodeScalars(scalars, mode: onEncodeError)
    }
}
