import Combine
import Foundation

enum PackCategory: String, Codable, CaseIterable, Identifiable {
    case sfw
    case nsfw
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sfw: return "SFW"
        case .nsfw: return "NSFW"
        case .custom: return "Custom"
        }
    }
}

struct SoundPack: Identifiable, Hashable {
    let id: String
    let name: String
    let category: PackCategory
    let files: [URL]
}

final class PackManager: ObservableObject {
    @Published private(set) var packs: [SoundPack] = []

    var defaultPackID: String { packs.first(where: { $0.category == .sfw })?.id ?? packs.first?.id ?? "sfw.default" }

    func reload(nsfwEnabled: Bool) {
        var result: [SoundPack] = []

        for packsRoot in candidatePackRoots() {
            result += loadBundled(at: packsRoot, category: .sfw, nsfwEnabled: nsfwEnabled)
            result += loadBundled(at: packsRoot, category: .nsfw, nsfwEnabled: nsfwEnabled)
        }

        result += loadCustomPacks()

        // Deduplicate by id
        var seen = Set<String>()
        packs = result.filter { pack in
            if seen.contains(pack.id) { return false }
            seen.insert(pack.id)
            return true
        }
    }

    private func candidatePackRoots() -> [URL] {
        var roots: [URL] = []
        if let moduleRoot = Bundle.module.resourceURL {
            roots.append(moduleRoot.appendingPathComponent("Packs"))
            roots.append(moduleRoot.appendingPathComponent("Resources/Packs"))
        }
        if let mainRoot = Bundle.main.resourceURL {
            roots.append(mainRoot.appendingPathComponent("Packs"))
            roots.append(mainRoot.appendingPathComponent("Resources/Packs"))
        }
        return roots
    }

    private func loadBundled(at root: URL, category: PackCategory, nsfwEnabled: Bool) -> [SoundPack] {
        if category == .nsfw && !nsfwEnabled { return [] }
        let categoryURL = root.appendingPathComponent(category.rawValue)
        guard let dirs = try? FileManager.default.contentsOfDirectory(
            at: categoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return dirs.compactMap { dir -> SoundPack? in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            let files = audioFiles(in: dir)
            guard !files.isEmpty else { return nil }
            let name = dir.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized
            return SoundPack(
                id: "\(category.rawValue).\(dir.lastPathComponent)",
                name: "\(category.label): \(name)",
                category: category,
                files: files
            )
        }
    }

    private func loadCustomPacks() -> [SoundPack] {
        let root = Paths.customPacksDirectory
        let fm = FileManager.default
        var packs: [SoundPack] = []

        // Flat files in Packs/
        let flat = audioFiles(in: root)
        if !flat.isEmpty {
            packs.append(SoundPack(id: "custom.root", name: "Custom: Drop folder", category: .custom, files: flat))
        }

        guard let dirs = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return packs }

        for dir in dirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let files = audioFiles(in: dir)
            guard !files.isEmpty else { continue }
            packs.append(
                SoundPack(
                    id: "custom.\(dir.lastPathComponent)",
                    name: "Custom: \(dir.lastPathComponent)",
                    category: .custom,
                    files: files
                )
            )
        }
        return packs
    }

    private func audioFiles(in directory: URL) -> [URL] {
        let allowed: Set<String> = ["wav", "mp3", "aiff", "m4a", "caf"]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items.filter { allowed.contains($0.pathExtension.lowercased()) }.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }
}
