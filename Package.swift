// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Speakin",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Speakin",
            path: "Sources/Speakin",
            exclude: [
                "Resources/Info.plist",
                "Resources/AppIcon.icns",
                "Resources/bird_capsule.png",
                "Resources/bird_capsule@2x.png",
                "Resources/bird_menubar.png",
                "Resources/bird_menubar@2x.png",
                "Resources/bird_menubar.svg",
                "Resources/bird_icon_32.png",
                "Resources/bird_icon_32@2x.png",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
