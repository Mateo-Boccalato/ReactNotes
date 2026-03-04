import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        let sceneStartTime = CFAbsoluteTimeGetCurrent()
        print("🚀 Scene setup starting...")
        
        guard let windowScene = scene as? UIWindowScene else { return }

        let dataStoreStart = CFAbsoluteTimeGetCurrent()
        let dataStore = DataStore.shared
        print("⏱️ DataStore.shared accessed (\(CFAbsoluteTimeGetCurrent() - dataStoreStart)s)")

        let splitVC = UISplitViewController(style: .doubleColumn)
        splitVC.preferredDisplayMode = .oneBesideSecondary
        splitVC.preferredSplitBehavior = .tile
        splitVC.presentsWithGesture = false
        splitVC.primaryBackgroundStyle = .sidebar
        splitVC.minimumPrimaryColumnWidth = 260
        splitVC.maximumPrimaryColumnWidth = 320

        let viewControllerStart = CFAbsoluteTimeGetCurrent()
        let sidebarVC = SidebarViewController(dataStore: dataStore)
        let gridVC = NoteGridViewController(dataStore: dataStore, filter: .all)
        let gridNav = UINavigationController(rootViewController: gridVC)
        print("⏱️ View controllers created (\(CFAbsoluteTimeGetCurrent() - viewControllerStart)s)")

        sidebarVC.delegate = gridVC

        splitVC.setViewController(sidebarVC, for: .primary)
        splitVC.setViewController(gridNav, for: .secondary)

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = splitVC
        window.makeKeyAndVisible()
        self.window = window
        
        print("✅ Scene setup complete! Total time: \(CFAbsoluteTimeGetCurrent() - sceneStartTime)s")
    }
}
