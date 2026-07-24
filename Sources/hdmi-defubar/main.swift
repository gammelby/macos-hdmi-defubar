import Foundation

if CommandLine.arguments.contains("--dump") {
    DumpCommand.run()
    exit(0)
}
print("hdmi-defubar: run with --dump, or wait for Task 10 for the app")
