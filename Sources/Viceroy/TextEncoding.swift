//===----------------------------------------------------------------------===//
// Viceroy — Static, per-encoding API (`TextEncoding`)
//
// Viceroy offers two doors, and the difference is what you pay for at link time:
//
//   • **Static** — `Encoding.ShiftJIS.decode(bytes)`. Resolved at compile time,
//     so the linker pulls in exactly one decoder and one table. A program that
//     only ever names UTF-8 links only UTF-8.
//
//   • **Dynamic** — `Encoding(label: someString)` then `.decode(bytes)`. The
//     label can name any of the 40 encodings, so the runtime switch necessarily
//     references all of them and the whole table set is linked. That is the
//     honest cost of runtime-chosen encodings — reach for the static door on
//     embedded targets, or wherever binary size matters.
//
// Both doors share the same engine, so results are identical.
//===----------------------------------------------------------------------===//

/// A statically-known encoding. Conformers are caseless enums used purely as
/// namespaces (`Encoding.Big5`), so there is nothing to allocate and every call
/// specializes — which keeps them usable from Embedded Swift.
public protocol TextEncoding {
    /// The WHATWG canonical name, e.g. `"Shift_JIS"`.
    static var name: String { get }
    static func decode(_ bytes: [UInt8], mode: DecodingErrorMode) throws(ViceroyError) -> String
    static func encode(_ string: String, mode: EncodingErrorMode) throws(ViceroyError) -> [UInt8]
}

extension TextEncoding {
    /// Decode using the WHATWG default (`.replacement`: emit U+FFFD and resync).
    @inlinable
    public static func decode(_ bytes: [UInt8]) throws(ViceroyError) -> String {
        try decode(bytes, mode: .replacement)
    }

    /// Encode, throwing on the first unrepresentable scalar.
    @inlinable
    public static func encode(_ string: String) throws(ViceroyError) -> [UInt8] {
        try encode(string, mode: .fatal)
    }
}
