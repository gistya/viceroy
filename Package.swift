// swift-tools-version: 6.0
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
