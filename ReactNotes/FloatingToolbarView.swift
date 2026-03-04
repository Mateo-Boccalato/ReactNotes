import UIKit
import PencilKit

// MARK: - Tool enum

enum DrawingTool: CaseIterable {
    case pen, pencil, eraser, text, lasso, hand

    var sfSymbol: String {
        switch self {
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .eraser: return "eraser"
        case .text: return "textformat"
        case .lasso: return "lasso"
        case .hand: return "hand.raised"
        }
    }

    func pkTool(color: UIColor, width: CGFloat) -> PKTool {
        switch self {
        case .pen: return PKInkingTool(.pen, color: color, width: width)
        case .pencil: return PKInkingTool(.pencil, color: color, width: width)
        case .eraser: return PKEraserTool(.vector)
        case .lasso: return PKLassoTool()
        case .text, .hand: return PKInkingTool(.pen, color: color, width: width)
        }
    }
}

// MARK: - FloatingToolbarDelegate

protocol FloatingToolbarDelegate: AnyObject {
    func toolbar(_ toolbar: FloatingToolbarView, didSelectTool tool: DrawingTool)
    func toolbar(_ toolbar: FloatingToolbarView, didSelectColor color: UIColor)
}

// MARK: - FloatingToolbarView

final class FloatingToolbarView: UIView {
    weak var delegate: FloatingToolbarDelegate?

    private(set) var selectedTool: DrawingTool = .pen
    private(set) var selectedColor: UIColor = .black

    private let stackView = UIStackView()
    private let colorSwatch = UIButton(type: .system)
    private let collapseButton = UIButton(type: .system)
    private var toolButtons: [DrawingTool: UIButton] = [:]
    private var isCollapsed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        backgroundColor = UIColor(white: 0.12, alpha: 0.95)
        layer.cornerRadius = 22
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.3

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.alignment = .center
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        buildToolButtons()
        buildColorSwatch()
        buildCollapseButton()
        selectTool(.pen)
    }

    private func buildToolButtons() {
        for tool in DrawingTool.allCases {
            let btn = makeToolButton(symbol: tool.sfSymbol)
            btn.tag = DrawingTool.allCases.firstIndex(of: tool)!
            btn.addTarget(self, action: #selector(toolTapped(_:)), for: .touchUpInside)
            toolButtons[tool] = btn

            if tool == .eraser {
                stackView.addArrangedSubview(btn)
                // Insert color swatch placeholder — added after loop
            } else {
                stackView.addArrangedSubview(btn)
            }

            // Insert color swatch after pencil
            if tool == .pencil {
                buildColorSwatchInStack()
            }
        }
    }

    private func buildColorSwatchInStack() {
        colorSwatch.translatesAutoresizingMaskIntoConstraints = false
        colorSwatch.backgroundColor = selectedColor
        colorSwatch.layer.cornerRadius = 12
        colorSwatch.layer.borderWidth = 2
        colorSwatch.layer.borderColor = UIColor.white.cgColor
        colorSwatch.addTarget(self, action: #selector(colorSwatchTapped), for: .touchUpInside)
        stackView.addArrangedSubview(colorSwatch)
        NSLayoutConstraint.activate([
            colorSwatch.widthAnchor.constraint(equalToConstant: 24),
            colorSwatch.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    private func buildColorSwatch() {
        // Already added inline during buildToolButtons
    }

    private func buildCollapseButton() {
        let btn = makeToolButton(symbol: "chevron.up")
        btn.addTarget(self, action: #selector(toggleCollapse), for: .touchUpInside)
        collapseButton.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(btn)
        // Keep reference
    }

    private func makeToolButton(symbol: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        btn.tintColor = .white
        btn.layer.cornerRadius = 20
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 40),
            btn.heightAnchor.constraint(equalToConstant: 40)
        ])
        return btn
    }

    // MARK: - Actions

    @objc private func toolTapped(_ sender: UIButton) {
        guard sender.tag < DrawingTool.allCases.count else { return }
        let tool = DrawingTool.allCases[sender.tag]
        selectTool(tool)
        delegate?.toolbar(self, didSelectTool: tool)
    }

    @objc private func colorSwatchTapped() {
        let picker = UIColorPickerViewController()
        picker.selectedColor = selectedColor
        picker.delegate = self
        picker.modalPresentationStyle = .popover
        picker.popoverPresentationController?.sourceView = colorSwatch
        picker.popoverPresentationController?.sourceRect = colorSwatch.bounds
        parentViewController?.present(picker, animated: true)
    }

    @objc private func toggleCollapse() {
        isCollapsed.toggle()
        UIView.animate(withDuration: 0.2) {
            for (_, btn) in self.toolButtons {
                btn.isHidden = self.isCollapsed
                btn.alpha = self.isCollapsed ? 0 : 1
            }
            self.colorSwatch.isHidden = self.isCollapsed
            self.colorSwatch.alpha = self.isCollapsed ? 0 : 1
        }
    }

    func selectTool(_ tool: DrawingTool) {
        selectedTool = tool
        for (t, btn) in toolButtons {
            btn.backgroundColor = t == tool ? UIColor.white.withAlphaComponent(0.2) : .clear
        }
    }

    func updateColor(_ color: UIColor) {
        selectedColor = color
        colorSwatch.backgroundColor = color
    }
}

// MARK: - UIColorPickerViewControllerDelegate

extension FloatingToolbarView: UIColorPickerViewControllerDelegate {
    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        let color = viewController.selectedColor
        updateColor(color)
        delegate?.toolbar(self, didSelectColor: color)
    }

    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        updateColor(color)
        // Always notify delegate so the color is applied immediately to the drawing tool
        delegate?.toolbar(self, didSelectColor: color)
    }
}

// MARK: - UIView parentViewController helper

private extension UIView {
    var parentViewController: UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }
}
