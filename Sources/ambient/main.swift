import AmbientCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

// The hook path runs on every agent event: keep it first, fast and silent.
if arguments.first == "hook" {
    Hook.run(arguments: Array(arguments.dropFirst()), paths: .current())
    exit(0)
}

exit(Commands(paths: .current()).run(arguments))
