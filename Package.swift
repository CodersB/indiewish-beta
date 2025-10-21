// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Upvote improvements
import PackageDescription

let package = Package(
    name: "IndieWish",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "IndieWish",
            targets: ["IndieWish"]
        ),
    ],
    targets: [
        .target(
            name: "IndieWish"
        ),
        .testTarget(
            name: "IndieWishTests",
            dependencies: ["IndieWish"]
        ),
    ]
)
