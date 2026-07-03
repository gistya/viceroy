import Foundation
import Testing
@testable import Viceroy

// Differential parity against the system `iconv` — "prove we match the thing we
// replace." Dev-only: set VICEROY_DIFF_ICONV=1 to run, and it self-skips where
// `/usr/bin/iconv` is absent (e.g. Windows CI). We compare only on the common
// CJK repertoire where the WHATWG set and iconv are known to agree (WHATWG
// deliberately diverges from iconv on some control-byte and HKSCS edges).

private func runIConv(_ input: [UInt8], from: String, to: String) -> [UInt8]? {
    let iconv = "/usr/bin/iconv"
    guard FileManager.default.isExecutableFile(atPath: iconv) else { return nil }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: iconv)
    p.arguments = ["-f", from, "-t", to]
    let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
    p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
    do { try p.run() } catch { return nil }
    inPipe.fileHandleForWriting.write(Data(input))
    try? inPipe.fileHandleForWriting.close()
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    _ = errPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? [UInt8](out) : nil
}

private let diffEnabled = ProcessInfo.processInfo.environment["VICEROY_DIFF_ICONV"] == "1"

private let cases: [(enc: Encoding, iconv: String, sample: String)] = [
    (.shiftJIS, "SHIFT-JIS", "あいうえおカタカナ漢字日本語テスト０１２"),
    (.eucJP,    "EUC-JP",    "あいうえお漢字日本語ＡＢＣ"),
    (.eucKR,    "EUC-KR",    "가나다라마바사한국어테스트"),
    (.big5,     "BIG5",      "中文字型測試繁體字"),
    (.utf8,     "UTF-8",     "Aあ漢字😀 café €—smart"),
    (.utf16le,  "UTF-16LE",  "Aあ漢字😀 café €"),
]

@Test(.enabled(if: diffEnabled, "set VICEROY_DIFF_ICONV=1 to run iconv parity tests"))
func differentialEncodeMatchesIconvDecode() throws {
    for c in cases {
        let ours = try c.enc.encode(c.sample, mode: .fatal)
        guard let back = runIConv(ours, from: c.iconv, to: "UTF-8") else {
            Issue.record("iconv unavailable/failed for \(c.iconv)"); continue
        }
        #expect(String(decoding: back, as: UTF8.self) == c.sample,
                "\(c.enc.name): iconv decoded our bytes differently")
    }
}

@Test(.enabled(if: diffEnabled, "set VICEROY_DIFF_ICONV=1 to run iconv parity tests"))
func differentialIconvEncodeMatchesOurDecode() throws {
    for c in cases {
        let utf8 = Array(c.sample.utf8)
        guard let iconvBytes = runIConv(utf8, from: "UTF-8", to: c.iconv) else {
            Issue.record("iconv unavailable/failed for \(c.iconv)"); continue
        }
        #expect(try c.enc.decode(iconvBytes, mode: .fatal) == c.sample,
                "\(c.enc.name): we decoded iconv's bytes differently")
    }
}
