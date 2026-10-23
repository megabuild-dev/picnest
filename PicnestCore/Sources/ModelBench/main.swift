import Foundation

let usage = """
ModelBench commands:
  sample <folder> <out> [--count 50] [--seed 1]
  categories <out>
  evaluate <out> [--cli-plan <plan.csv>] [--models <dir>]
"""

do {
    var args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty else { print(usage); exit(2) }
    let command = args.removeFirst()
    switch command {
    case "sample": try runSample(args)
    case "categories": try runCategories(args)
    case "evaluate": try await runEvaluate(args)
    default: print(usage); exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
