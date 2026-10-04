// swift-tools-version: 5.9

import PackageDescription

let release = "https://github.com/pinge/litert-xcframework/releases/download/v2.2.0"

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
      checksum: "81039e06794fe86f05e98ab82c7a14e42fd438233492cf1550092717b492e367"
    ),
    .binaryTarget(
      name: "LiteRTMetalAccelerator",
      url: "\(release)/LiteRTMetalAccelerator.xcframework.zip",
      checksum: "617bccc040fcce5fef11bf067ad6159320978893a6bceca8e5f7bcb5959d0896"
    ),
  ]
)
