import UIKit
import PencilKit

actor ThumbnailCache {
    static let shared = ThumbnailCache()
    private var cache: [String: UIImage] = [:]

    func thumbnail(for note: Note, size: CGSize) async -> UIImage? {
        if let cached = cache[note.id] { return cached }
        guard let data = note.canvasData,
              let drawing = try? PKDrawing(data: data) else { return nil }
        let img = await Task.detached(priority: .utility) {
            drawing.image(from: CGRect(origin: .zero, size: size), scale: 1)
        }.value
        cache[note.id] = img
        return img
    }

    func invalidate(noteId: String) {
        cache.removeValue(forKey: noteId)
    }
}
