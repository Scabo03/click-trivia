// swift-tools-version: 6.0

// ClickTriviaKit — tutta la logica dell'app vive qui, in moduli che rispecchiano
// le fasi di sviluppo. Il target dell'app è solo un guscio sottile.
//
//   Fondamenta (Fase 0):  TriviaCore, TriviaAccessibility, TriviaDesign, TriviaPersistence
//   Fase 2 (import):      TriviaImport      (solo protocolli, per ora)
//   Fase 3 (presenza):    TriviaNearby      (solo protocolli — Multipeer Connectivity)
//   Fase 4 (distanza):    TriviaRemote      (solo protocolli — CloudKit)
//
// Regola di dipendenza: tutti i moduli dipendono da TriviaCore; TriviaCore non
// dipende da nessuno (dominio puro, senza UI né framework di sistema).

import PackageDescription

let package = Package(
    name: "ClickTriviaKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "TriviaCore", targets: ["TriviaCore"]),
        .library(name: "TriviaAccessibility", targets: ["TriviaAccessibility"]),
        .library(name: "TriviaDesign", targets: ["TriviaDesign"]),
        .library(name: "TriviaPersistence", targets: ["TriviaPersistence"]),
        .library(name: "TriviaImport", targets: ["TriviaImport"]),
        .library(name: "TriviaNearby", targets: ["TriviaNearby"]),
        .library(name: "TriviaRemote", targets: ["TriviaRemote"]),
    ],
    targets: [
        .target(name: "TriviaCore"),
        .target(name: "TriviaAccessibility", dependencies: ["TriviaCore"]),
        .target(name: "TriviaDesign", dependencies: ["TriviaCore", "TriviaAccessibility"]),
        .target(name: "TriviaPersistence", dependencies: ["TriviaCore"]),
        .target(name: "TriviaImport", dependencies: ["TriviaCore"]),
        .target(name: "TriviaNearby", dependencies: ["TriviaCore"]),
        .target(name: "TriviaRemote", dependencies: ["TriviaCore"]),
        .testTarget(name: "TriviaCoreTests", dependencies: ["TriviaCore"]),
        .testTarget(name: "TriviaImportTests", dependencies: ["TriviaImport"]),
        .testTarget(name: "TriviaNearbyTests", dependencies: ["TriviaNearby"]),
    ]
)
