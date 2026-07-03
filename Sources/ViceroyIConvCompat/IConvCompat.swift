//===----------------------------------------------------------------------===//
// ViceroyIConvCompat — a thin `iconv_open`/`iconv`/`iconv_close`-shaped adapter
// over `Transcoder`, for porting existing libiconv call sites with minimal edits.
//
// This is opt-in (`import ViceroyIConvCompat`). New code should prefer Viceroy's
// native API (`Encoding`, `Transcoder`, `StreamingDecoder/Encoder`). Like the
// rest of Viceroy, this module has no dependencies and does not import Foundation.
//===----------------------------------------------------------------------===//

import Viceroy

/// An open conversion descriptor, analogous to `iconv_t` from `iconv_open`.
///
/// The `toCode` may carry the familiar iconv suffixes `//IGNORE` (drop
/// unrepresentable characters) and `//TRANSLIT` (here approximated as `?`),
/// e.g. `IConv(fromCode: "SHIFT_JIS", toCode: "UTF-8//IGNORE")`.
public struct IConv: Sendable {
    public let transcoder: Transcoder

    /// Like `iconv_open(tocode, fromcode)`. Returns `nil` if either label is
    /// unknown — the analogue of `iconv_open` returning `(iconv_t)-1`.
    public init?(fromCode: String, toCode: String) {
        // iconv labels never contain '/', so the label is the first slash-part
        // and any trailing parts are `//IGNORE` / `//TRANSLIT` markers.
        let parts = toCode.split(separator: "/", omittingEmptySubsequences: true)
        let toLabel = parts.first.map(String.init) ?? ""
        var encodeError: EncodingErrorMode = .fatal
        for marker in parts.dropFirst() {
            switch marker.lowercased() {
            case "ignore":   encodeError = .drop
            case "translit": encodeError = .replacement(0x3F)
            default:         break
            }
        }
        guard let from = Encoding(label: fromCode),
              let dst = Encoding(label: toLabel) else { return nil }
        self.transcoder = Transcoder(from: from, to: dst,
                                     onDecodeError: .replacement, onEncodeError: encodeError)
    }

    /// Convert a whole buffer, analogous to draining `iconv()` in one call.
    /// Throws in the fatal encode case (no `//IGNORE`/`//TRANSLIT`), like `iconv`
    /// returning `EILSEQ` on an unrepresentable character.
    public func convert(_ input: [UInt8]) throws -> [UInt8] {
        try transcoder.transcode(input)
    }
}
