//===----------------------------------------------------------------------===//
// Viceroy — Encoding identity
//===----------------------------------------------------------------------===//

/// Which decoder/encoder family an `Encoding` selects. The single-byte case
/// carries an index into the generated single-byte table registry.
@usableFromInline
enum Scheme: Sendable, Hashable {
    case utf8
    case utf16le
    case utf16be
    /// A generic 128-entry single-byte encoding; payload indexes `_singleByteTables`.
    case singleByte(UInt8)
    case shiftJIS
    case eucJP
    case iso2022JP
    case big5
    case gbk
    case gb18030
    case eucKR
    /// WHATWG "replacement": any non-empty input decodes to a single U+FFFD.
    case replacement
    /// WHATWG "x-user-defined".
    case xUserDefined
}

/// The identity of a character encoding — a WHATWG-canonical name plus the
/// family that implements it. Value type, `Sendable`, `Hashable`.
///
/// Construct one from a label (`Encoding(label: "latin1")`) or use a static
/// (`Encoding.windows1252`). Then call `decode`/`encode`/`decodeScalars`.
public struct Encoding: Sendable, Hashable, CustomStringConvertible {
    /// The WHATWG canonical name, e.g. `"Shift_JIS"`, `"windows-1252"`, `"gb18030"`.
    public let name: String
    @usableFromInline let scheme: Scheme

    @usableFromInline
    init(name: String, scheme: Scheme) {
        self.name = name
        self.scheme = scheme
    }

    /// Look up an encoding by *label*, per the WHATWG "get an encoding" algorithm:
    /// strip leading/trailing ASCII whitespace (TAB, LF, FF, CR, SPACE), lowercase
    /// ASCII, then match against the ~220-entry alias table. Returns `nil` for an
    /// unknown label. Note WHATWG quirks: `iso-8859-1`/`latin1` → `windows-1252`.
    public init?(label: String) {
        // WHATWG "get an encoding", done entirely on UTF-8 bytes: trim ASCII
        // whitespace (TAB, LF, FF, CR, SPACE), lowercase ASCII, then binary-search
        // the label table. No String case-folding or hashing anywhere — those need
        // Unicode data tables, which would bar Embedded Swift use.
        @inline(__always) func isWS(_ b: UInt8) -> Bool {
            b == 0x09 || b == 0x0A || b == 0x0C || b == 0x0D || b == 0x20
        }
        var buf = [UInt8]()
        buf.reserveCapacity(label.utf8.count)
        for b in label.utf8 {
            buf.append((b >= 0x41 && b <= 0x5A) ? b &+ 0x20 : b)
        }
        var start = 0, end = buf.count
        while start < end, isWS(buf[start]) { start += 1 }
        while end > start, isWS(buf[end - 1]) { end -= 1 }
        guard let idx = lookupLabel(buf[start..<end]) else { return nil }
        self = Encoding(name: _canonicalNames[idx], scheme: _schemes[idx])
    }

    public var description: String { name }

    // `name` is uniquely determined by `scheme`, so identity is the scheme alone.
    // Hashing on the scheme (a plain integer enum) rather than the `String` name
    // keeps `Encoding` free of Unicode-normalization dependencies.
    public static func == (lhs: Encoding, rhs: Encoding) -> Bool { lhs.scheme == rhs.scheme }
    public func hash(into hasher: inout Hasher) { hasher.combine(scheme) }
}

// MARK: - Well-known encodings

extension Encoding {
    // UTF family
    public static let utf8      = Encoding(name: "UTF-8", scheme: .utf8)
    public static let utf16le   = Encoding(name: "UTF-16LE", scheme: .utf16le)
    public static let utf16be   = Encoding(name: "UTF-16BE", scheme: .utf16be)

    // Single-byte (indices must match the generated `_singleByteTables` order)
    public static let ibm866        = Encoding(name: "IBM866", scheme: .singleByte(0))
    public static let iso8859_2     = Encoding(name: "ISO-8859-2", scheme: .singleByte(1))
    public static let iso8859_3     = Encoding(name: "ISO-8859-3", scheme: .singleByte(2))
    public static let iso8859_4     = Encoding(name: "ISO-8859-4", scheme: .singleByte(3))
    public static let iso8859_5     = Encoding(name: "ISO-8859-5", scheme: .singleByte(4))
    public static let iso8859_6     = Encoding(name: "ISO-8859-6", scheme: .singleByte(5))
    public static let iso8859_7     = Encoding(name: "ISO-8859-7", scheme: .singleByte(6))
    public static let iso8859_8     = Encoding(name: "ISO-8859-8", scheme: .singleByte(7))
    public static let iso8859_8I    = Encoding(name: "ISO-8859-8-I", scheme: .singleByte(8))
    public static let iso8859_10    = Encoding(name: "ISO-8859-10", scheme: .singleByte(9))
    public static let iso8859_13    = Encoding(name: "ISO-8859-13", scheme: .singleByte(10))
    public static let iso8859_14    = Encoding(name: "ISO-8859-14", scheme: .singleByte(11))
    public static let iso8859_15    = Encoding(name: "ISO-8859-15", scheme: .singleByte(12))
    public static let iso8859_16    = Encoding(name: "ISO-8859-16", scheme: .singleByte(13))
    public static let koi8r         = Encoding(name: "KOI8-R", scheme: .singleByte(14))
    public static let koi8u         = Encoding(name: "KOI8-U", scheme: .singleByte(15))
    public static let macintosh     = Encoding(name: "macintosh", scheme: .singleByte(16))
    public static let windows874    = Encoding(name: "windows-874", scheme: .singleByte(17))
    public static let windows1250   = Encoding(name: "windows-1250", scheme: .singleByte(18))
    public static let windows1251   = Encoding(name: "windows-1251", scheme: .singleByte(19))
    public static let windows1252   = Encoding(name: "windows-1252", scheme: .singleByte(20))
    public static let windows1253   = Encoding(name: "windows-1253", scheme: .singleByte(21))
    public static let windows1254   = Encoding(name: "windows-1254", scheme: .singleByte(22))
    public static let windows1255   = Encoding(name: "windows-1255", scheme: .singleByte(23))
    public static let windows1256   = Encoding(name: "windows-1256", scheme: .singleByte(24))
    public static let windows1257   = Encoding(name: "windows-1257", scheme: .singleByte(25))
    public static let windows1258   = Encoding(name: "windows-1258", scheme: .singleByte(26))
    public static let xMacCyrillic  = Encoding(name: "x-mac-cyrillic", scheme: .singleByte(27))

    // CJK
    public static let shiftJIS    = Encoding(name: "Shift_JIS", scheme: .shiftJIS)
    public static let eucJP       = Encoding(name: "EUC-JP", scheme: .eucJP)
    public static let iso2022JP   = Encoding(name: "ISO-2022-JP", scheme: .iso2022JP)
    public static let big5        = Encoding(name: "Big5", scheme: .big5)
    public static let gbk         = Encoding(name: "GBK", scheme: .gbk)
    public static let gb18030     = Encoding(name: "gb18030", scheme: .gb18030)
    public static let eucKR       = Encoding(name: "EUC-KR", scheme: .eucKR)

    // Special
    public static let replacement    = Encoding(name: "replacement", scheme: .replacement)
    public static let xUserDefined   = Encoding(name: "x-user-defined", scheme: .xUserDefined)
}
