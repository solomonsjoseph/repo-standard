// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "__PKG__",
  products: [.library(name: "__PKG__", targets: ["__PKG__"])],
  targets: [
    .target(name: "__PKG__"),
    .testTarget(name: "__PKG__Tests", dependencies: ["__PKG__"]),
  ]
)
