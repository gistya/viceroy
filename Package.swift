// swift-tools-version: 6.1
//
// Viceroy — a pure-Swift, zero-dependency character-encoding library.
// A full replacement for libiconv, targeting the WHATWG Encoding Standard.
//
// There are deliberately NO `dependencies:` here, and no `import Foundation`
// anywhere in the shipping `Viceroy` / `ViceroyIConvCompat` targets. Both
// invariants are enforced by `NoFoundationGuardTests`.

import PackageDescription

let package = Package(
    name: "Viceroy",
    products: [
        // The library. Depend on this.
        .library(name: "Viceroy", targets: ["Viceroy"]),
        // Opt-in `iconv_open`/`iconv`/`iconv_close`-shaped adapter for C porters.
        .library(name: "ViceroyIConvCompat", targets: ["ViceroyIConvCompat"]),
    ],
    // Encoding families are opt-OUT. Every trait is enabled by default, so an
    // ordinary `.package(url:from:)` gets all 40 encodings exactly as before.
    // Constrained targets can disable families they don't need; the tables and
    // decoders are then never compiled in, which is the only thing that actually
    // shrinks the binary (unused code alone does not reliably dead-strip —
    // protocol conformance records keep it live).
    //
    //   .package(url: "…/viceroy.git", from: "1.1.0",
    //            traits: ["SingleByte"])      // UTF + single-byte only
    traits: [
        .trait(name: "Chinese",    description: "Big5, GBK and gb18030 (~370 KB of tables)"),
        .trait(name: "Japanese",   description: "Shift_JIS, EUC-JP, ISO-2022-JP (~90 KB of tables)"),
        .trait(name: "Korean",     description: "EUC-KR / UHC (~145 KB of tables)"),
        .trait(name: "SingleByte", description: "The 28 single-byte legacy encodings (~20 KB)"),
        .default(enabledTraits: ["Chinese", "Japanese", "Korean", "SingleByte"]),
        .trait(name: "none", enabledTraits: []),
    ],
    targets: [
        // The shipping library. Zero dependencies, no Foundation.
        .target(name: "Viceroy"),
        // Thin iconv-shaped adapter over `Transcoder`.
        .target(
            name: "ViceroyIConvCompat",
            dependencies: ["Viceroy"]
        ),

        // Dev-only regeneration tool. NOT part of the shipping surface — it may
        // use Foundation. Reads `vendor/whatwg/*` and emits `Sources/Viceroy/Tables/*.swift`.
        .executableTarget(
            name: "viceroy-tablegen",
            path: "Tools/viceroy-tablegen"
        ),

        // Dev-only throughput benchmark (`swift run -c release viceroy-bench`).
        .executableTarget(
            name: "viceroy-bench",
            dependencies: ["Viceroy"],
            path: "Tools/viceroy-bench"
        ),

        // Tests.
        .testTarget(name: "ViceroyTests", dependencies: ["Viceroy"]),
        // Conformance harness reads the vendored WHATWG index files directly
        // (via a `#filePath`-relative path) as the oracle — no resource bundle,
        // no Bundle.module, no Foundation-heavy packaging.
        .testTarget(name: "ConformanceTests", dependencies: ["Viceroy"]),
    ]
)
