import AppKit
import UserNotifications

class ServiceHandler: NSObject {

    @objc func convertToPDF(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let items = pboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return }

        let mdFiles = items.filter { $0.pathExtension.lowercased() == "md" }
        guard !mdFiles.isEmpty else { return }

        for url in mdFiles { convert(url) }
    }

    private func convert(_ url: URL) {
        guard let binary = findMd2pdf() else {
            notify("md2pdf not found", body: "Install md2pdf to ~/.local/bin or ~/.cargo/bin")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binary)
        proc.arguments = [url.path]
        let errPipe = Pipe()
        proc.standardError = errPipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            notify("md2pdf error", body: error.localizedDescription)
            return
        }

        if proc.terminationStatus == 0 {
            let pdf = url.deletingPathExtension().appendingPathExtension("pdf").lastPathComponent
            notify("Converted", body: "\(pdf) ready")
        } else {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            notify("md2pdf failed", body: msg.isEmpty ? url.lastPathComponent : msg)
        }
    }

    private func findMd2pdf() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/md2pdf",
            "\(home)/.cargo/bin/md2pdf",
            "/usr/local/bin/md2pdf",
            "/opt/homebrew/bin/md2pdf",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func notify(_ title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
