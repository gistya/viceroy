import Foundation
import Testing

// The whole point of Viceroy is zero dependencies. These tests fail loudly if a
// `import Foundation` (or any platform-conditional import) ever sneaks into the
// shipping library — the invariant that lets it compile identically on macOS,
// Linux, and Windows with nothing to install.

private let repoRoot: URL =
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func swiftSources(under relativeDir: String) -> [URL] {
    let dir = repoRoot.appendingPathComponent(relativeDir)
    guard let it = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
    return it.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
}

@Test func shippingLibraryImportsNothingButSwift() throws {
    // Only `Viceroy` itself must import nothing; `ViceroyIConvCompat` may import
    // `Viceroy`. Match real statements at line-start so prose in comments (which
    // legitimately mentions "Foundation") doesn't trip the guard.
    let bannedModules: Set<String> = ["Foundation", "Darwin", "Glibc", "WinSDK", "ucrt", "CoreFoundation"]
    for target in ["Sources/Viceroy", "Sources/ViceroyIConvCompat"] {
        let files = swiftSources(under: target)
        #expect(!files.isEmpty, "no sources found under \(target)")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            // `.isNewline` so a CRLF checkout can't collapse the file to one line
            // and let a banned `import` slip through undetected.
            for rawLine in text.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("import ") {
                    let module = line.dropFirst("import ".count)
                        .split(whereSeparator: { $0 == " " || $0 == ";" }).first.map(String.init) ?? ""
                    #expect(!bannedModules.contains(module),
                            "\(file.lastPathComponent) imports banned module `\(module)`")
                }
                #expect(!line.hasPrefix("#if os("),
                        "\(file.lastPathComponent) has a platform conditional")
            }
        }
    }
}
