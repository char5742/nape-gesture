import Foundation

let tool = CommandLineTool(arguments: CommandLine.arguments)

do {
    try tool.run()
} catch {
    fputs("エラー: \(error.localizedDescription)\n", stderr)
    exit(1)
}
