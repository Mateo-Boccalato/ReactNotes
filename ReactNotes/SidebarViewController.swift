import UIKit

// MARK: - Filter enum

enum NoteFilter: Equatable {
    case all
    case recents
    case favorites
    case unfiled
    case notebook(String)
}

// MARK: - SidebarDelegate protocol

protocol SidebarDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarViewController, didSelectFilter filter: NoteFilter)
}

// MARK: - SidebarViewController

final class SidebarViewController: UIViewController {
    private let dataStore: DataStore
    weak var delegate: SidebarDelegate?

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .grouped)

    private var notebooks: [Notebook] = []
    private var selectedFilter: NoteFilter = .all

    // Flattened row model
    private enum SidebarRow {
        case allNotes(count: Int)
        case gallery
        case notebook(Notebook)
    }
    private var fixedRows: [SidebarRow] = []
    private var notebookRows: [SidebarRow] = []

    private static let sidebarBackground = UIColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)
    private static let selectedBackground = UIColor(white: 1, alpha: 0.1)

    init(dataStore: DataStore) {
        self.dataStore = dataStore
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.sidebarBackground
        configureSearchBar()
        configureTableView()
        reloadData()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDataChanged),
            name: .appDataDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration

    private func configureSearchBar() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        searchBar.placeholder = "Search"
        searchBar.barStyle = .black
        searchBar.searchBarStyle = .minimal
        searchBar.tintColor = .white
        if let tf = searchBar.value(forKey: "searchField") as? UITextField {
            tf.textColor = .white
            tf.attributedPlaceholder = NSAttributedString(
                string: "Search",
                attributes: [.foregroundColor: UIColor.systemGray]
            )
        }
        view.addSubview(searchBar)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SidebarCell.self, forCellReuseIdentifier: SidebarCell.reuseId)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Data

    @objc private func handleDataChanged() {
        reloadData()
    }

    private func reloadData() {
        notebooks = dataStore.notebooksSorted()
        rebuildRows()
        tableView.reloadData()
    }

    private func rebuildRows() {
        let totalNotes = dataStore.appData.notes.count
        fixedRows = [.allNotes(count: totalNotes), .gallery]

        notebookRows = notebooks.map { .notebook($0) }
    }

    // MARK: - Actions

    @objc private func addNotebook() {
        let alert = UIAlertController(title: "New Notebook", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Notebook name" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self else { return }
            let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = self.dataStore.createNotebook(title: name?.isEmpty == false ? name! : "Untitled Notebook")
        })
        present(alert, animated: true)
    }

    private func selectFilter(_ filter: NoteFilter) {
        selectedFilter = filter
        delegate?.sidebar(self, didSelectFilter: filter)
        tableView.reloadData()
    }

    private func showNotebookContextMenu(for notebook: Notebook, at indexPath: IndexPath) {
        let alert = UIAlertController(title: notebook.title, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.presentRenameAlert(for: notebook)
        })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.dataStore.deleteNotebook(id: notebook.id)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView.cellForRow(at: indexPath)
            popover.sourceRect = tableView.cellForRow(at: indexPath)?.bounds ?? .zero
        }
        present(alert, animated: true)
    }

    private func presentRenameAlert(for notebook: Notebook) {
        let alert = UIAlertController(title: "Rename Notebook", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = notebook.title
            tf.placeholder = "Notebook name"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            self?.dataStore.updateNotebook(id: notebook.id, title: name)
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SidebarViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? fixedRows.count : notebookRows.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = indexPath.section == 0 ? fixedRows[indexPath.row] : notebookRows[indexPath.row]
        switch row {
        case .allNotes(let count):
            let cell = tableView.dequeueReusableCell(withIdentifier: SidebarCell.reuseId, for: indexPath) as! SidebarCell
            cell.configure(
                icon: "note.text",
                title: "Notes",
                badge: count > 0 ? "\(count)" : nil,
                isSelected: selectedFilter == .all,
                indented: false
            )
            return cell

        case .gallery:
            let cell = tableView.dequeueReusableCell(withIdentifier: SidebarCell.reuseId, for: indexPath) as! SidebarCell
            cell.configure(
                icon: "photo.on.rectangle",
                title: "Gallery",
                badge: nil,
                isSelected: false,
                indented: false
            )
            return cell

        case .notebook(let nb):
            let cell = tableView.dequeueReusableCell(withIdentifier: SidebarCell.reuseId, for: indexPath) as! SidebarCell
            cell.configure(
                icon: "book.closed",
                title: nb.title,
                badge: nil,
                isSelected: selectedFilter == .notebook(nb.id),
                indented: false,
                folderColor: nb.color.flatMap { UIColor(hex: $0) }
            )
            return cell
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard section == 1 else { return nil }
        let header = UIView()
        header.backgroundColor = .clear

        let label = UILabel()
        label.text = "NOTEBOOKS"
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .systemGray
        label.translatesAutoresizingMaskIntoConstraints = false

        let addButton = UIButton(type: .system)
        addButton.setImage(UIImage(systemName: "plus"), for: .normal)
        addButton.tintColor = .systemGray
        addButton.addTarget(self, action: #selector(addNotebook), for: .touchUpInside)
        addButton.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(label)
        header.addSubview(addButton)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            addButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 28)
        ])
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        section == 1 ? 36 : 0
    }
}

// MARK: - UITableViewDelegate

extension SidebarViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = indexPath.section == 0 ? fixedRows[indexPath.row] : notebookRows[indexPath.row]

        switch row {
        case .allNotes:
            selectFilter(.all)
        case .gallery:
            break
        case .notebook(let nb):
            selectFilter(.notebook(nb.id))
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        44
    }

    func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.section == 1 else { return nil }
        let row = notebookRows[indexPath.row]
        guard case .notebook(let notebook) = row else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu(title: "", children: []) }
            let rename = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.presentRenameAlert(for: notebook)
            }
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.dataStore.deleteNotebook(id: notebook.id)
            }
            return UIMenu(title: notebook.title, children: [rename, delete])
        }
    }
}

// MARK: - UIColor hex extension

extension UIColor {
    convenience init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - SidebarCell

final class SidebarCell: UITableViewCell {
    static let reuseId = "SidebarCell"

    private let iconView = UIImageView()
    private let folderDot = UIView()
    private let titleLabel = UILabel()
    private let badgeLabel = UILabel()
    private let chevronView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectedBackgroundView = {
            let v = UIView()
            v.backgroundColor = UIColor(white: 1, alpha: 0.1)
            return v
        }()

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .systemGray
        iconView.contentMode = .scaleAspectFit

        folderDot.translatesAutoresizingMaskIntoConstraints = false
        folderDot.layer.cornerRadius = 5
        folderDot.isHidden = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 15)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.textColor = .systemGray
        badgeLabel.font = .systemFont(ofSize: 13)

        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.tintColor = .systemGray
        chevronView.isHidden = true

        contentView.addSubview(iconView)
        contentView.addSubview(folderDot)
        contentView.addSubview(titleLabel)
        contentView.addSubview(badgeLabel)
        contentView.addSubview(chevronView)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            folderDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            folderDot.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            folderDot.widthAnchor.constraint(equalToConstant: 10),
            folderDot.heightAnchor.constraint(equalToConstant: 10),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -8),

            badgeLabel.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -6),
            badgeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            chevronView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            chevronView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 14),
            chevronView.heightAnchor.constraint(equalToConstant: 14)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(
        icon: String?,
        title: String,
        badge: String?,
        isSelected: Bool,
        indented: Bool,
        folderColor: UIColor? = nil,
        showChevron: Bool = false,
        chevronExpanded: Bool = false
    ) {
        if let icon {
            iconView.image = UIImage(systemName: icon)
            iconView.isHidden = false
            folderDot.isHidden = true
        } else if let color = folderColor {
            folderDot.backgroundColor = color
            folderDot.isHidden = false
            iconView.isHidden = true
        }

        titleLabel.text = title
        titleLabel.font = isSelected ? .systemFont(ofSize: 15, weight: .semibold) : .systemFont(ofSize: 15)
        badgeLabel.text = badge
        badgeLabel.isHidden = badge == nil
        backgroundColor = isSelected ? UIColor(white: 1, alpha: 0.08) : .clear

        if showChevron {
            chevronView.isHidden = false
            let chevronName = chevronExpanded ? "chevron.down" : "chevron.right"
            chevronView.image = UIImage(systemName: chevronName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        } else {
            chevronView.isHidden = true
        }
    }
}

