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
        // and any trailing parts are `//IGNORE` / `//TRANSLIT` markers. Split and
        // compare on UTF-8 bytes — `String.lowercased()` would pull in Unicode
        // case-mapping tables and bar Embedded Swift use.
        var parts: [[UInt8]] = []
        var cur: [UInt8] = []
        for b in toCode.utf8 {
            if b == 0x2F {                       // '/'
                if !cur.isEmpty { parts.append(cur); cur = [] }
            } else {
                cur.append(b)
            }
        }
        if !cur.isEmpty { parts.append(cur) }

        let toLabel = parts.first.map { String(decoding: $0, as: UTF8.self) } ?? ""
        var encodeError: EncodingErrorMode = .fatal
        for marker in parts.dropFirst() {
            let lower = marker.map { (b: UInt8) in (b >= 0x41 && b <= 0x5A) ? b &+ 0x20 : b }
            if lower == Array("ignore".utf8) { encodeError = .drop }
            else if lower == Array("translit".utf8) { encodeError = .replacement(0x3F) }
        }
        guard let from = Encoding(label: fromCode),
              let dst = Encoding(label: toLabel) else { return nil }
        self.transcoder = Transcoder(from: from, to: dst,
                                     onDecodeError: .replacement, onEncodeError: encodeError)
    }

    /// Convert a whole buffer, analogous to draining `iconv()` in one call.
    /// Throws in the fatal encode case (no `//IGNORE`/`//TRANSLIT`), like `iconv`
    /// returning `EILSEQ` on an unrepresentable character.
    public func convert(_ input: [UInt8]) throws(ViceroyError) -> [UInt8] {
        try transcoder.transcode(input)
    }
}
