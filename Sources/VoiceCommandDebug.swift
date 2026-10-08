import Foundation

enum VoiceCommandDebug {
    private static let queue = DispatchQueue(label: "CapturE.VoiceCommandDebug")

    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [VOICE DEBUG] \(message)"
        print(line)
        queue.async {
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let url = directory.appendingPathComponent("voice_debug.log")
            let data = Data((line + "\n").utf8)
            do {
                if !FileManager.default.fileExists(atPath: url.path) {
                    try data.write(to: url, options: .atomic)
                } else {
                    let handle = try FileHandle(forWritingTo: url)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.synchronize()
                }
            } catch {
                print("[VOICE DEBUG] Log write failed: \(error.localizedDescription)")
            }
        }
    }
}
