//===----------------------------------------------------------------------===//
// viceroy-bench — a rough throughput benchmark. Dev-only (may use Foundation).
//   swift run -c release viceroy-bench
//===----------------------------------------------------------------------===//

import Foundation
import Viceroy

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func time(_ label: String, bytes: Int, _ body: () -> Void) {
    // Warm up, then take the best of a few runs.
    body()
    var best = Double.greatestFiniteMagnitude
    for _ in 0..<5 {
        let t0 = now(); body(); best = min(best, now() - t0)
    }
    let mbps = (Double(bytes) / 1_000_000) / best
    let name = label.padding(toLength: 28, withPad: " ", startingAt: 0)
    let rate = String(format: "%8.1f", mbps)
    let ms = String(format: "%.3f", best * 1000)
    print("  \(name) \(rate) MB/s  (\(ms) ms)")
}

// Build a ~8 MB sample document (ASCII-heavy with CJK + accents, like real XML).
let unit = "<name>Aあ漢字 café €</name> Hello, 世界! ABCDEFG 0123456789\n"
var doc = ""
while doc.utf8.count < 8_000_000 { doc += unit }
let utf8Bytes = Array(doc.utf8)
print("sample: \(utf8Bytes.count) UTF-8 bytes\n")

print("Decode (bytes → String):")
time("Viceroy UTF-8", bytes: utf8Bytes.count) {
    _ = try! Encoding.utf8.decode(utf8Bytes)
}
time("stdlib String(decoding:UTF8)", bytes: utf8Bytes.count) {
    _ = String(decoding: utf8Bytes, as: UTF8.self)
}

// windows-1252 sample (single byte).
let latin = Array(repeating: UInt8(0x41), count: 4_000_000)
    + (0x80...0xFF).map { UInt8($0) } .flatMap { Array(repeating: $0, count: 1) }
print("\nDecode single-byte (windows-1252):")
time("Viceroy windows-1252", bytes: latin.count) {
    _ = try! Encoding.windows1252.decode(latin)
}

// Shift_JIS round-trip encode.
let sjis = try! Encoding.shiftJIS.encode(doc, mode: .questionMark)
print("\nDecode multibyte (Shift_JIS, \(sjis.count) bytes):")
time("Viceroy Shift_JIS", bytes: sjis.count) {
    _ = try! Encoding.shiftJIS.decode(sjis)
}

print("\nEncode (String → bytes):")
time("Viceroy UTF-8 encode", bytes: utf8Bytes.count) {
    _ = try! Encoding.utf8.encode(doc)
}
