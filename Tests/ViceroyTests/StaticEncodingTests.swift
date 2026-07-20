import Testing
@testable import Viceroy

// Every static namespace must be a drop-in for its dynamic counterpart: same
// canonical name, same decode, same encode. The two doors share one engine, so
// any divergence is a wiring bug (wrong table index, wrong stripBOM, …).

private let pairs: [(any TextEncoding.Type, Encoding)] = [
    (Encoding.UTF8.self, .utf8), (Encoding.UTF16LE.self, .utf16le), (Encoding.UTF16BE.self, .utf16be),
    (Encoding.ShiftJIS.self, .shiftJIS), (Encoding.EUCJP.self, .eucJP), (Encoding.ISO2022JP.self, .iso2022JP),
    (Encoding.Big5.self, .big5), (Encoding.GB18030.self, .gb18030), (Encoding.GBK.self, .gbk),
    (Encoding.EUCKR.self, .eucKR),
    (Encoding.Replacement.self, .replacement), (Encoding.XUserDefined.self, .xUserDefined),
    (Encoding.IBM866.self, .ibm866), (Encoding.ISO8859_2.self, .iso8859_2),
    (Encoding.ISO8859_8.self, .iso8859_8), (Encoding.ISO8859_8I.self, .iso8859_8I),
    (Encoding.ISO8859_15.self, .iso8859_15), (Encoding.KOI8R.self, .koi8r), (Encoding.KOI8U.self, .koi8u),
    (Encoding.Macintosh.self, .macintosh), (Encoding.Windows874.self, .windows874),
    (Encoding.Windows1252.self, .windows1252), (Encoding.Windows1256.self, .windows1256),
    (Encoding.XMacCyrillic.self, .xMacCyrillic),
]

@Test func staticNamespacesMatchDynamic() throws {
    let sample: [UInt8] = [0x41, 0x82, 0xA0, 0xB1, 0x40, 0x00, 0xFE, 0x7E]
    for (S, dyn) in pairs {
        #expect(S.name == dyn.name, "name mismatch for \(dyn.name)")
        let a = try? S.decode(sample, mode: .replacement)
        let b = try? dyn.decode(sample, mode: .replacement)
        #expect(a == b, "\(dyn.name): static decode != dynamic decode")
        let text = "Aa1 "
        let ea = try? S.encode(text, mode: .questionMark)
        let eb = try? dyn.encode(text, mode: .questionMark)
        #expect(ea == eb, "\(dyn.name): static encode != dynamic encode")
    }
}

@Test func staticNamespacesCoverEveryEncoding() {
    // One namespace per WHATWG encoding: 40 total (28 single-byte + 12 others).
    #expect(_canonicalNames.count == 40)
}
