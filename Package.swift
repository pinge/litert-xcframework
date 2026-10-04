// swift-tools-version: 5.9

import PackageDescription

let release = "https://github.com/pinge/litert-xcframework/releases/download/v2.1.6"

let package = Package(
  name: "LiteRT",
  platforms: [
    .iOS(.v15),
  ],
  products: [
    .library(
      name: "LiteRT",
      targets: [
        "CLiteRT",
        "LiteRTMetalAccelerator",
      ]
    ),
  ],
  targets: [
    .binaryTarget(
      name: "CLiteRT",
      url: "\(release)/CLiteRT.xcframework.zip",
      checksum: "621cbf3716fe22a59091422bdac80128f47fb11a079c3c0cf837417545372060"
    ),
    .binaryTarget(
      name: "LiteRTMetalAccelerator",
      url: "\(release)/LiteRTMetalAccelerator.xcframework.zip",
      checksum: "bbcb3b5854daa1735988b6f1db77064eb6789cfa23b8833ecc6221ee2d0dc981"
    ),
  ]
)
