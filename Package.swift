// swift-tools-version: 5.10
import PackageDescription

let package = Package(
	name: "Timerette",
	platforms: [.macOS(.v13)],
	targets: [
		.executableTarget(
			name: "timerette",
			path: "Sources/timerette",
			linkerSettings: [
				.linkedFramework("Carbon"),
			]
		),
	]
)
