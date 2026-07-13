import Foundation
import SPUAccel

let args = CommandLine.arguments
var socketPath = ProcessInfo.processInfo.environment["SLAPME_SOCKET"]
    ?? FileManager.default.temporaryDirectory.appendingPathComponent("slapme.sock").path
var minAmplitude = 0.05
var cooldown = 0.65
var verbose = false

func printUsage() {
    print("""
    slapme-helper — Apple Silicon SPU slap detector (requires sudo)

    Usage:
      sudo slapme-helper [--socket PATH] [--threshold 0.05] [--cooldown 0.65] [-v]

    Emits JSON lines on a Unix domain socket:
      {"type":"hello","version":1}
      {"type":"slap","amplitude":0.12,"ts":1710000000.0}
    """)
}

var i = 1
while i < args.count {
    switch args[i] {
    case "--socket":
        i += 1
        if i < args.count { socketPath = args[i] }
    case "--threshold", "--min-amplitude":
        i += 1
        if i < args.count, let v = Double(args[i]) { minAmplitude = v }
    case "--cooldown":
        i += 1
        if i < args.count, let v = Double(args[i]) { cooldown = v }
    case "--verbose", "-v":
        verbose = true
    case "--help", "-h":
        printUsage()
        exit(0)
    default:
        fputs("Unknown argument: \(args[i])\n", stderr)
    }
    i += 1
}

if getuid() != 0 {
    fputs("slapme-helper requires root (IOKit HID). Re-run with sudo.\n", stderr)
    exit(1)
}

let server = SocketServer(path: socketPath)
do {
    try server.start()
} catch {
    fputs("Failed to start socket server at \(socketPath): \(error)\n", stderr)
    exit(1)
}

print("SlapMe helper listening on \(socketPath)")
fflush(stdout)

let accel = SPUAccelerometer(
    minAmplitude: minAmplitude,
    cooldownSeconds: cooldown,
    callbackQueue: DispatchQueue(label: "com.slapme.helper.callbacks")
)

accel.onSlap = { event in
    let line = #"{"type":"slap","amplitude":\#(String(format: "%.6f", event.amplitude)),"ts":\#(event.timestamp)}"# + "\n"
    server.broadcast(line)
    if verbose {
        print("slap amp=\(String(format: "%.4f", event.amplitude))")
    }
}

signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }

do {
    try accel.start()
    RunLoop.main.run()
} catch {
    fputs("Sensor failed: \(error)\n", stderr)
    exit(1)
}
