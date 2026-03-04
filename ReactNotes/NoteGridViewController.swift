import UIKit

final class NoteGridViewController: UIViewController {
    private let dataStore: DataStore
    private(set) var filter: NoteFilter

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, String>!
    private var allNotes: [Note] = []
    private var filteredNotes: [Note] = []

    private let filterControl = UISegmentedControl(items: ["All", "Recents", "Favorites", "Unfiled"])
    private var activeTab: Int = 0

    init(dataStore: DataStore, filter: NoteFilter) {
        self.dataStore = dataStore
        self.filter = filter
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        let viewLoadStart = CFAbsoluteTimeGetCurrent()
        print("📱 NoteGridViewController viewDidLoad starting...")
        
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        configureNavigation()
        configureFilterControl()
        configureCollectionView()
        configureDataSource()
        reloadData()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDataChanged),
            name: .appDataDidChange,
            object: nil
        )
        
        print("⏱️ NoteGridViewController viewDidLoad complete (\(CFAbsoluteTimeGetCurrent() - viewLoadStart)s)")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration

    private func configureNavigation() {
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.largeTitleDisplayMode = .always
        title = "Notes"

        let addButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(addNote)
        )
        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(showMore)
        )
        navigationItem.rightBarButtonItems = [addButton, moreButton]
    }

    private func configureFilterControl() {
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        filterControl.selectedSegmentIndex = 0
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)
        view.addSubview(filterControl)
        NSLayoutConstraint.activate([
            filterControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            filterControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            filterControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    private func configureCollectionView() {
        let layout = makeLayout()
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.register(NoteCardCell.self, forCellWithReuseIdentifier: NoteCardCell.reuseId)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 8),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(0.5),
            heightDimension: .estimated(240)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        // Use edgeSpacing instead of contentInsets for estimated dimensions
        item.edgeSpacing = NSCollectionLayoutEdgeSpacing(
            leading: .fixed(8),
            top: .fixed(6),
            trailing: .fixed(8),
            bottom: .fixed(6)
        )

        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(240)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item, item])

        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 20, trailing: 8)

        return UICollectionViewCompositionalLayout(section: section)
    }

    private func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { [weak self] cv, indexPath, noteId in
            guard let self,
                  let note = self.filteredNotes.first(where: { $0.id == noteId }) else {
                return cv.dequeueReusableCell(withReuseIdentifier: NoteCardCell.reuseId, for: indexPath)
            }
            let cell = cv.dequeueReusableCell(withReuseIdentifier: NoteCardCell.reuseId, for: indexPath) as! NoteCardCell
            cell.configure(note: note, thumbnail: nil)
            // Async load thumbnail
            Task {
                let img = await ThumbnailCache.shared.thumbnail(for: note, size: CGSize(width: 300, height: 160))
                await MainActor.run {
                    // Re-fetch cell in case it was reused
                    if let current = cv.cellForItem(at: indexPath) as? NoteCardCell {
                        current.setThumbnail(img)
                    }
                }
            }
            return cell
        }
    }

    // MARK: - Data

    @objc private func handleDataChanged() {
        reloadData()
    }

    private func reloadData() {
        switch filter {
        case .all:
            allNotes = dataStore.allNotesSorted()
            title = "Notes"
        case .folder(let id):
            allNotes = dataStore.notes(inFolder: id)
            title = dataStore.appData.folders.first(where: { $0.id == id })?.name ?? "Notes"
        case .notebook(let id):
            allNotes = dataStore.notes(in: id)
            title = dataStore.appData.notebooks.first(where: { $0.id == id })?.title ?? "Notes"
        case .recents:
            allNotes = Array(dataStore.allNotesSorted().prefix(20))
            title = "Recents"
        case .favorites:
            allNotes = dataStore.allNotesSorted().filter(\.isFavorite)
            title = "Favorites"
        case .unfiled:
            let notebookIds = Set(dataStore.appData.notebooks.map(\.id))
            allNotes = dataStore.allNotesSorted().filter { !notebookIds.contains($0.notebookId) }
            title = "Unfiled"
        }

        applyTabFilter()
    }

    private func applyTabFilter() {
        switch activeTab {
        case 1: // Recents
            filteredNotes = Array(allNotes.prefix(20))
        case 2: // Favorites
            filteredNotes = allNotes.filter(\.isFavorite)
        case 3: // Unfiled
            let notebookIds = Set(dataStore.appData.notebooks.map(\.id))
            filteredNotes = allNotes.filter { !notebookIds.contains($0.notebookId) }
        default:
            filteredNotes = allNotes
        }

        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(filteredNotes.map(\.id))
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    // MARK: - Actions

    @objc private func filterChanged() {
        activeTab = filterControl.selectedSegmentIndex
        applyTabFilter()
    }

    @objc private func addNote() {
        // Determine notebook to create in
        let notebookId: String
        switch filter {
        case .notebook(let id):
            notebookId = id
        case .folder(let folderId):
            if let nb = dataStore.notebooks(in: folderId).first {
                notebookId = nb.id
            } else {
                let nb = dataStore.createNotebook(in: folderId)
                notebookId = nb.id
            }
        default:
            if let nb = dataStore.appData.notebooks.first {
                notebookId = nb.id
            } else {
                return
            }
        }
        let note = dataStore.createNote(in: notebookId)
        let editor = NoteEditorViewController(dataStore: dataStore, noteId: note.id)
        navigationController?.pushViewController(editor, animated: true)
    }

    @objc private func showMore() {
        // Placeholder for sort/view options
    }
}

// MARK: - SidebarDelegate

extension NoteGridViewController: SidebarDelegate {
    func sidebar(_ sidebar: SidebarViewController, didSelectFilter filter: NoteFilter) {
        self.filter = filter
        activeTab = 0
        filterControl.selectedSegmentIndex = 0
        reloadData()
    }
}

// MARK: - UICollectionViewDelegate

extension NoteGridViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard indexPath.row < filteredNotes.count else { return }
        let note = filteredNotes[indexPath.row]
        let editor = NoteEditorViewController(dataStore: dataStore, noteId: note.id)
        navigationController?.pushViewController(editor, animated: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.row < filteredNotes.count else { return nil }
        let note = filteredNotes[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu(title: "", children: []) }
            let favTitle = note.isFavorite ? "Unfavorite" : "Favorite"
            let favIcon = note.isFavorite ? "star.slash" : "star"
            let favorite = UIAction(title: favTitle, image: UIImage(systemName: favIcon)) { [weak self] _ in
                self?.dataStore.toggleFavorite(id: note.id)
            }
            let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.dataStore.deleteNote(id: note.id)
            }
            return UIMenu(title: "", children: [favorite, delete])
        }
    }
}
