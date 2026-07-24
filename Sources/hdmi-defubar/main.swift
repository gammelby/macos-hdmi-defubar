import Foundation

if CommandLine.arguments.contains("--dump") {
    DumpCommand.run()
    exit(0)
}
DefubarApp.main()
