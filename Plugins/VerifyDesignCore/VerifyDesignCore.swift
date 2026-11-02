import Foundation
import PackagePlugin

@main
struct VerifyDesignCore: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let output = context.pluginWorkDirectoryURL.appending(path: "verified")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        return [.prebuildCommand(
            displayName: "Verify shared Ouros design core",
            executable: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: [context.package.directoryURL.appending(path: ".design-core/generate.py").path, "--check"],
            environment: ["PYTHONDONTWRITEBYTECODE": "1"],
            outputFilesDirectory: output
        )]
    }
}
