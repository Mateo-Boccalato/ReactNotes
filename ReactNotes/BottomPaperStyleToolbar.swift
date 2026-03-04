import UIKit

// MARK: - Paper style enum

enum PaperStyle: CaseIterable {
    case lined, grid, dot, blank

    var label: String {
        switch self {
        case .lined: return "Lined"
        case .grid: return "Grid"
        case .dot: return "Dot"
        case .blank: return "Blank"
        }
    }

    var sfSymbol: String {
        switch self {
        case .lined: return "line.3.horizontal"
        case .grid: return "squareshape.split.2x2"
        case .dot: return "circle.grid.3x3"
        case .blank: return "doc"
        }
    }
}

// MARK: - BottomPaperStyleToolbarDelegate

protocol BottomPaperStyleToolbarDelegate: AnyObject {
    func toolbar(_ toolbar: BottomPaperStyleToolbar, didSelectStyle style: PaperStyle)
    func toolbarDidTapAddPhoto(_ toolbar: BottomPaperStyleToolbar)
}

// MARK: - BottomPaperStyleToolbar

final class BottomPaperStyleToolbar: UIView {
    weak var delegate: BottomPaperStyleToolbarDelegate?
    private(set) var selectedStyle: PaperStyle = .lined
    
    private var backgroundButton: UIButton!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        backgroundColor = .systemGray6

        // Top border
        let border = UIView()
        border.translatesAutoresizingMaskIntoConstraints = false
        border.backgroundColor = UIColor.systemGray4
        addSubview(border)
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: topAnchor),
            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        // Create horizontal stack for all buttons
        let mainStack = UIStackView()
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.axis = .horizontal
        mainStack.spacing = 12
        mainStack.distribution = .fillEqually
        mainStack.alignment = .center

        addSubview(mainStack)

        // Create background selector button with menu
        backgroundButton = makeBackgroundButton()
        
        // Create add photo button
        let photoBtn = makeUtilityButton(symbol: "photo.on.rectangle.angled", title: "Add Photo")
        photoBtn.addTarget(self, action: #selector(addPhotoTapped), for: .touchUpInside)
        
        mainStack.addArrangedSubview(backgroundButton)
        mainStack.addArrangedSubview(photoBtn)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            mainStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        ])

        selectStyle(.lined)
    }
    
    @objc private func addPhotoTapped() {
        delegate?.toolbarDidTapAddPhoto(self)
    }

    private func makeBackgroundButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: selectedStyle.sfSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
        config.title = "Background"
        config.imagePadding = 4
        config.imagePlacement = .top
        config.baseForegroundColor = .systemBlue
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)

        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.titleLabel?.font = .systemFont(ofSize: 10)
        btn.showsMenuAsPrimaryAction = true
        btn.menu = createBackgroundMenu()
        
        return btn
    }
    
    private func createBackgroundMenu() -> UIMenu {
        var actions: [UIAction] = []
        
        for style in PaperStyle.allCases {
            let action = UIAction(
                title: style.label,
                image: UIImage(systemName: style.sfSymbol),
                state: style == selectedStyle ? .on : .off
            ) { [weak self] _ in
                self?.selectStyle(style)
                self?.delegate?.toolbar(self!, didSelectStyle: style)
            }
            actions.append(action)
        }
        
        return UIMenu(title: "Paper Style", children: actions)
    }

    private func makeUtilityButton(symbol: String, title: String) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
        config.title = title
        config.imagePadding = 4
        config.imagePlacement = .top
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)

        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.titleLabel?.font = .systemFont(ofSize: 10)
        return btn
    }

    func selectStyle(_ style: PaperStyle) {
        selectedStyle = style
        
        // Update button icon to match selected style
        var config = backgroundButton.configuration
        config?.image = UIImage(systemName: style.sfSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
        backgroundButton.configuration = config
        
        // Recreate menu with updated selection state
        backgroundButton.menu = createBackgroundMenu()
    }
}

// MARK: - PatternBackgroundView

final class PatternBackgroundView: UIView {
    var style: PaperStyle = .lined { didSet { setNeedsDisplay() } }
    var spacing: CGFloat = 28
    var usePageMode: Bool = false { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        // Background color
        if usePageMode {
            UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1).setFill()
        } else {
            UIColor.white.setFill()
        }
        ctx.fill(rect)

        let lineColor = UIColor.systemBlue.withAlphaComponent(0.15)
        lineColor.setStroke()
        ctx.setLineWidth(0.5)

        switch style {
        case .blank:
            break

        case .lined:
            var y = spacing
            while y < rect.height {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += spacing
            }
            ctx.strokePath()

        case .grid:
            var y = spacing
            while y < rect.height {
                ctx.move(to: CGPoint(x: rect.minX, y: y))
                ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
                y += spacing
            }
            var x = spacing
            while x < rect.width {
                ctx.move(to: CGPoint(x: x, y: rect.minY))
                ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
                x += spacing
            }
            ctx.strokePath()

        case .dot:
            let dotColor = UIColor.systemBlue.withAlphaComponent(0.25)
            dotColor.setFill()
            var y = spacing
            while y < rect.height {
                var x = spacing
                while x < rect.width {
                    let dotRect = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                    ctx.fillEllipse(in: dotRect)
                    x += spacing
                }
                y += spacing
            }
        }
    }
}
// MARK: - PageContainerView

final class PageContainerView: UIView {
    private let pageNumberLabel = UILabel()
    
    init(pageNumber: Int) {
        super.init(frame: .zero)
        setupPageView(pageNumber: pageNumber)
    }
    
    required init?(coder: NSCoder) { nil }
    
    private func setupPageView(pageNumber: Int) {
        backgroundColor = .white
        layer.cornerRadius = 4
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.15
        
        // Page number label at bottom center
        pageNumberLabel.translatesAutoresizingMaskIntoConstraints = false
        pageNumberLabel.text = "\(pageNumber)"
        pageNumberLabel.font = .systemFont(ofSize: 11)
        pageNumberLabel.textColor = .systemGray
        pageNumberLabel.textAlignment = .center
        addSubview(pageNumberLabel)
        
        NSLayoutConstraint.activate([
            pageNumberLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            pageNumberLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
        ])
    }
}


