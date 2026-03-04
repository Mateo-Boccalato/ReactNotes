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
}

// MARK: - BottomPaperStyleToolbar

final class BottomPaperStyleToolbar: UIView {
    weak var delegate: BottomPaperStyleToolbarDelegate?
    private(set) var selectedStyle: PaperStyle = .lined

    private let stackView = UIStackView()
    private var styleButtons: [PaperStyle: UIButton] = [:]

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

        // Create left stack for paper styles (equal distribution)
        let leftStack = UIStackView()
        leftStack.translatesAutoresizingMaskIntoConstraints = false
        leftStack.axis = .horizontal
        leftStack.spacing = 0
        leftStack.distribution = .fillEqually
        leftStack.alignment = .center
        
        // Create right stack for utility buttons (equal distribution)
        let rightStack = UIStackView()
        rightStack.translatesAutoresizingMaskIntoConstraints = false
        rightStack.axis = .horizontal
        rightStack.spacing = 0
        rightStack.distribution = .fillEqually
        rightStack.alignment = .center

        addSubview(leftStack)
        addSubview(rightStack)

        // Add paper style buttons to left stack
        for style in PaperStyle.allCases {
            let btn = makeButton(for: style)
            styleButtons[style] = btn
            leftStack.addArrangedSubview(btn)
        }

        // Add separator (not in any stack, positioned independently)
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = UIColor.systemGray4
        addSubview(separator)

        // Add utility buttons to right stack
        let importBtn = makeUtilityButton(symbol: "arrow.up.doc", title: "Import")
        let scanBtn = makeUtilityButton(symbol: "doc.text.viewfinder", title: "Scan")
        rightStack.addArrangedSubview(importBtn)
        rightStack.addArrangedSubview(scanBtn)

        NSLayoutConstraint.activate([
            // Left stack
            leftStack.topAnchor.constraint(equalTo: topAnchor),
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            leftStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            
            // Separator
            separator.leadingAnchor.constraint(equalTo: leftStack.trailingAnchor, constant: 8),
            separator.centerYAnchor.constraint(equalTo: centerYAnchor),
            separator.widthAnchor.constraint(equalToConstant: 0.5),
            separator.heightAnchor.constraint(equalToConstant: 24),
            
            // Right stack
            rightStack.topAnchor.constraint(equalTo: topAnchor),
            rightStack.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 8),
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rightStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            
            // Make left and right stacks equal width
            leftStack.widthAnchor.constraint(equalTo: rightStack.widthAnchor, multiplier: 2.0)
        ])

        selectStyle(.lined)
    }

    private func makeButton(for style: PaperStyle) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: style.sfSymbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
        config.title = style.label
        config.imagePadding = 4
        config.imagePlacement = .top
        config.baseForegroundColor = .secondaryLabel
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)

        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.tag = PaperStyle.allCases.firstIndex(of: style)!
        btn.addTarget(self, action: #selector(styleTapped(_:)), for: .touchUpInside)
        btn.titleLabel?.font = .systemFont(ofSize: 10)
        return btn
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

    @objc private func styleTapped(_ sender: UIButton) {
        guard sender.tag < PaperStyle.allCases.count else { return }
        let style = PaperStyle.allCases[sender.tag]
        selectStyle(style)
        delegate?.toolbar(self, didSelectStyle: style)
    }

    func selectStyle(_ style: PaperStyle) {
        selectedStyle = style
        for (s, btn) in styleButtons {
            var config = btn.configuration
            config?.baseForegroundColor = s == style ? .systemBlue : .secondaryLabel
            btn.configuration = config
        }
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


