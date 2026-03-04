import UIKit

final class NoteCardCell: UICollectionViewCell {
    static let reuseId = "NoteCardCell"

    private let containerView = UIView()
    private let thumbnailView = UIImageView()
    private let placeholderView = UIView()
    private let placeholderIcon = UIImageView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = 12
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowRadius = 4
        containerView.layer.shadowOpacity = 0.12
        containerView.clipsToBounds = false

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.backgroundColor = UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        thumbnailView.layer.cornerRadius = 12
        thumbnailView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.backgroundColor = UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
        placeholderView.layer.cornerRadius = 12
        placeholderView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        placeholderIcon.translatesAutoresizingMaskIntoConstraints = false
        placeholderIcon.image = UIImage(systemName: "note.text")
        placeholderIcon.tintColor = UIColor.systemGray3
        placeholderIcon.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .darkText  // Changed from .label to ensure dark text on white background
        titleLabel.numberOfLines = 2

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 11)
        dateLabel.textColor = .darkGray  // Changed from .secondaryLabel to ensure readable gray text

        contentView.addSubview(containerView)
        containerView.addSubview(thumbnailView)
        containerView.addSubview(placeholderView)
        placeholderView.addSubview(placeholderIcon)
        containerView.addSubview(titleLabel)
        containerView.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            thumbnailView.topAnchor.constraint(equalTo: containerView.topAnchor),
            thumbnailView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            thumbnailView.heightAnchor.constraint(equalTo: containerView.heightAnchor, multiplier: 0.65),

            placeholderView.topAnchor.constraint(equalTo: containerView.topAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            placeholderView.heightAnchor.constraint(equalTo: containerView.heightAnchor, multiplier: 0.65),

            placeholderIcon.centerXAnchor.constraint(equalTo: placeholderView.centerXAnchor),
            placeholderIcon.centerYAnchor.constraint(equalTo: placeholderView.centerYAnchor),
            placeholderIcon.widthAnchor.constraint(equalToConstant: 36),
            placeholderIcon.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),

            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 10),
            dateLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -10),
            dateLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -8)
        ])
    }

    func configure(note: Note, thumbnail: UIImage?) {
        titleLabel.text = note.title.isEmpty ? "Untitled" : note.title
        dateLabel.text = formatDate(note.updatedAt)
        setThumbnail(thumbnail)
    }

    func setThumbnail(_ image: UIImage?) {
        if let image {
            thumbnailView.image = image
            thumbnailView.isHidden = false
            placeholderView.isHidden = true
        } else {
            thumbnailView.image = nil
            thumbnailView.isHidden = true
            placeholderView.isHidden = false
        }
    }

    private func formatDate(_ isoString: String) -> String {
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: isoString) else { return isoString }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailView.image = nil
        thumbnailView.isHidden = true
        placeholderView.isHidden = false
    }
}
