import Testing
@testable import Viceroy

// The UTF-8 replacement-mode fast path delegates to the stdlib's
// `String(decoding:as:UTF8.self)`. This proves the stdlib's U+FFFD substitution
// is byte-for-byte identical to our explicit WHATWG state machine across a large
// adversarial corpus, so the fast path is a safe optimization — not a shortcut.

private func stateMachineDecode(_ bytes: [UInt8]) -> String {
    // Drive the explicit state machine (not the fast path) into a scalar view.
    var driver = DecodeDriver(UTF8Decoder(), mode: .replacement)
    var view = String.UnicodeScalarView()
    try! driver.feed(bytes, into: &view)
    try! driver.finish(into: &view)
    return String(view)
}

@Test func utf8StdlibMatchesStateMachine() {
    // Deterministic pseudo-random byte sequences (no Foundation RNG; LCG).
    var state: UInt64 = 0x9E3779B97F4A7C15
    func next() -> UInt8 { state = state &* 6364136223846793005 &+ 1442695040888963407; return UInt8((state >> 33) & 0xFF) }

    for trial in 0..<4000 {
        let n = Int(next()) % 24
        var bytes = [UInt8]()
        for _ in 0..<n {
            // Bias toward multibyte lead/continuation bytes to hit edge cases.
            let r = next()
            bytes.append(r < 0x40 ? r : (0x80 | (r & 0x7F)))
        }
        let viaStdlib = String(decoding: bytes, as: UTF8.self)
        let viaMachine = stateMachineDecode(bytes)
        #expect(viaStdlib == viaMachine, "trial \(trial): \(bytes)")
    }

    // Explicit adversarial vectors.
    let vectors: [[UInt8]] = [
        [0x80], [0xBF], [0xC0, 0x80], [0xE0, 0x80, 0x80], [0xF0, 0x80, 0x80, 0x80],
        [0xED, 0xA0, 0x80], [0xF4, 0x90, 0x80, 0x80], [0xE2, 0x82], [0xF0, 0x9F, 0x98],
        [0xC2], [0xFE], [0xFF], [0x41, 0xC3, 0x28], [0xF0, 0x28, 0x8C, 0xBC],
    ]
    for v in vectors {
        #expect(String(decoding: v, as: UTF8.self) == stateMachineDecode(v), "vector \(v)")
    }
}
