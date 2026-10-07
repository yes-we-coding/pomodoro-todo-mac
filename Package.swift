// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PomodoroTodo",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "PomodoroTodo",
            path: "Sources/PomodoroTodo"
        )
    ]
)
