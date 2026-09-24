import Foundation

enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case text
    case link
    case image
    case file
    case richText

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "文字"
        case .link: "链接"
        case .image: "图片"
        case .file: "文件"
        case .richText: "富文本"
        }
    }
}

struct ClipboardEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let kind: ClipKind
    let preview: String
    let maskedPreview: String
    let fullText: String?
    let imagePath: String?
    let filePaths: [String]
    let sourceAppName: String
    let sourceBundleID: String?
    let sourceColorHex: String
    let checksum: String
    var isFavorite: Bool

    init(
        id: UUID,
        createdAt: Date,
        kind: ClipKind,
        preview: String,
        maskedPreview: String,
        fullText: String?,
        imagePath: String?,
        filePaths: [String],
        sourceAppName: String,
        sourceBundleID: String?,
        sourceColorHex: String,
        checksum: String,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.preview = preview
        self.maskedPreview = maskedPreview
        self.fullText = fullText
        self.imagePath = imagePath
        self.filePaths = filePaths
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.sourceColorHex = sourceColorHex
        self.checksum = checksum
        self.isFavorite = isFavorite
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case kind
        case preview
        case maskedPreview
        case fullText
        case imagePath
        case filePaths
        case sourceAppName
        case sourceBundleID
        case sourceColorHex
        case checksum
        case isFavorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decode(ClipKind.self, forKey: .kind)
        preview = try container.decode(String.self, forKey: .preview)
        maskedPreview = try container.decode(String.self, forKey: .maskedPreview)
        fullText = try container.decodeIfPresent(String.self, forKey: .fullText)
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        filePaths = try container.decode([String].self, forKey: .filePaths)
        sourceAppName = try container.decode(String.self, forKey: .sourceAppName)
        sourceBundleID = try container.decodeIfPresent(String.self, forKey: .sourceBundleID)
        sourceColorHex = try container.decode(String.self, forKey: .sourceColorHex)
        checksum = try container.decode(String.self, forKey: .checksum)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

enum TimeScope: String, CaseIterable, Identifiable {
    case oneDay
    case sevenDays
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneDay: "一天"
        case .sevenDays: "七天"
        case .favorites: "收藏"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .oneDay: 24 * 60 * 60
        case .sevenDays: 7 * 24 * 60 * 60
        case .favorites: .infinity
        }
    }
}

enum KindFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case link
    case image
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .text: "文字"
        case .link: "链接"
        case .image: "图片"
        case .file: "文件"
        }
    }

    func matches(_ kind: ClipKind) -> Bool {
        switch self {
        case .all:
            true
        case .text:
            kind == .text || kind == .richText
        case .link:
            kind == .link
        case .image:
            kind == .image
        case .file:
            kind == .file
        }
    }
}
