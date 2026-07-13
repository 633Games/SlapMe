import Foundation

struct SoundboardClip: Identifiable, Hashable {
    let id: String
    let title: String
    let fileName: String
    let audioURL: URL
}

enum SoundboardError: LocalizedError {
    case badQuery
    case badResponse
    case parseFailed
    case downloadFailed(String)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .badQuery: return "Enter a search term."
        case .badResponse: return "Soundboard didn’t respond. Try again later."
        case .parseFailed: return "Couldn’t parse soundboard results."
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .writeFailed: return "Couldn’t save the audio file."
        }
    }
}

enum SoundboardImporter {
    private static let searchBase = "https://www.myinstants.com/en/search/?name="
    private static let mediaBase = "https://www.myinstants.com/media/sounds/"
    private static let userAgent = "SlapMe/1.0 (macOS; soundboard importer; +https://ko-fi.com/633games)"

    static func search(query: String) async throws -> [SoundboardClip] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SoundboardError.badQuery }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?")
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        guard let url = URL(string: searchBase + encoded) else { throw SoundboardError.badQuery }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8)
        else {
            throw SoundboardError.badResponse
        }

        let clips = parse(html: html)
        guard !clips.isEmpty else { throw SoundboardError.parseFailed }
        return clips
    }

    static func download(_ clip: SoundboardClip, into directory: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var request = URLRequest(url: clip.audioURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
            throw SoundboardError.downloadFailed("HTTP error")
        }

        let safe = sanitizeFileName(clip.title.isEmpty ? clip.fileName : clip.title)
        let ext = (clip.fileName as NSString).pathExtension.isEmpty ? "mp3" : (clip.fileName as NSString).pathExtension
        var dest = directory.appendingPathComponent("\(safe).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = directory.appendingPathComponent("\(safe)-\(n).\(ext)")
            n += 1
        }

        do {
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            throw SoundboardError.writeFailed
        }
    }

    /// Best-effort scrape of MyInstants search HTML.
    private static func parse(html: String) -> [SoundboardClip] {
        var clips: [SoundboardClip] = []
        var seen = Set<String>()

        // onclick="play('/media/sounds/file.mp3', …)" title="Play Foo sound"
        let pattern = #"play\('/media/sounds/([^']+\.mp3)'[^)]*\)"\s*title="Play ([^"]+?)(?: sound)?""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                guard let match,
                      let fileRange = Range(match.range(at: 1), in: html),
                      let titleRange = Range(match.range(at: 2), in: html)
                else { return }
                let fileName = String(html[fileRange])
                guard !seen.contains(fileName) else { return }
                seen.insert(fileName)
                let title = String(html[titleRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let audioURL = URL(string: mediaBase + fileName) else { return }
                clips.append(
                    SoundboardClip(
                        id: fileName,
                        title: title.isEmpty ? fileName : title,
                        fileName: fileName,
                        audioURL: audioURL
                    )
                )
            }
        }

        // Fallback: unique media paths only
        if clips.isEmpty {
            let fallback = #"/media/sounds/([^"'\s>]+\.mp3)"#
            if let regex = try? NSRegularExpression(pattern: fallback, options: [.caseInsensitive]) {
                let range = NSRange(html.startIndex..<html.endIndex, in: html)
                regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
                    guard let match, let fileRange = Range(match.range(at: 1), in: html) else { return }
                    let fileName = String(html[fileRange])
                    guard !seen.contains(fileName) else { return }
                    seen.insert(fileName)
                    guard let audioURL = URL(string: mediaBase + fileName) else { return }
                    let title = (fileName as NSString).deletingPathExtension
                        .replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: "-", with: " ")
                    clips.append(
                        SoundboardClip(id: fileName, title: title, fileName: fileName, audioURL: audioURL)
                    )
                }
            }
        }

        return Array(clips.prefix(40))
    }

    private static func sanitizeFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let filtered = String(cleaned.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        let collapsed = filtered.replacingOccurrences(of: "\\-+", with: "-", options: .regularExpression)
        return String(collapsed.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "- "))
            .nilIfEmpty ?? "sound"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
