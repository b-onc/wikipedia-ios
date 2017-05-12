import UIKit

@objc(WMFExploreViewController)
class ExploreViewController: UIViewController, WMFExploreCollectionViewControllerDelegate, UISearchBarDelegate, AnalyticsViewNameProviding, AnalyticsContextProviding
{
    public var collectionViewController: WMFExploreCollectionViewController!

    @IBOutlet weak var extendedNavBarView: UIView!
    @IBOutlet weak var containerView: UIView!
    @IBOutlet weak var extendNavBarViewTopSpaceConstraint: NSLayoutConstraint!
    @IBOutlet weak var searchBar: UISearchBar!
    
    private var searchBarButtonItem: WMFSearchButton?
    
    public var userStore: MWKDataStore? {
        didSet {
            guard let newValue = userStore else {
                assertionFailure("cannot set CollectionViewController.userStore to nil")
                return
            }
            collectionViewController.userStore = newValue
        }
    }
    
    public var titleButton: UIButton? {
        guard let button = self.navigationItem.titleView as? UIButton else {
            return nil
        }
        return button
    }
    
    required init?(coder aDecoder: NSCoder) {
         super.init(coder: aDecoder)

        // manually instiate child exploreViewController
        // originally did via an embed segue but this caused the `exploreViewController` to load too late
        let storyBoard = UIStoryboard(name: "Explore", bundle: nil)
        let vc = storyBoard.instantiateViewController(withIdentifier: "CollectionViewController")
        guard let collectionViewController = (vc as? WMFExploreCollectionViewController) else {
            assertionFailure("Could not load WMFExploreCollectionViewController")
            return nil
        }
        self.collectionViewController = collectionViewController
        self.collectionViewController.delegate = self

        let b = UIButton(type: .custom)
        b.adjustsImageWhenHighlighted = true
        b.setImage(#imageLiteral(resourceName: "wikipedia"), for: UIControlState.normal)
        b.sizeToFit()
        b.addTarget(self, action: #selector(titleBarButtonPressed), for: UIControlEvents.touchUpInside)
        self.navigationItem.titleView = b
        self.navigationItem.isAccessibilityElement = true
        self.navigationItem.accessibilityTraits |= UIAccessibilityTraitHeader
        
        self.searchBarButtonItem = self.wmf_searchBarButtonItem()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .wmf_settingsBackground
        self.view.tintColor = .wmf_blueTint
        
        // programmatically add sub view controller
        // originally did via an embed segue but this caused the `exploreViewController` to load too late
        self.collectionViewController.willMove(toParentViewController: self)
        self.containerView.addSubview(collectionViewController.view)
        self.addChildViewController(collectionViewController)
        self.collectionViewController.didMove(toParentViewController: self)

        self.navigationItem.leftBarButtonItem = settingsBarButtonItem()
        self.navigationItem.rightBarButtonItem = self.searchBarButtonItem
        
        self.wmf_addBottomShadow(view: extendedNavBarView)
        
        self.searchBar.placeholder = WMFLocalizedString("search-field-placeholder-text", value:"Search Wikipedia", comment:"Search field placeholder text")
    }

    override func viewWillAppear(_ animated: Bool) {
        self.wmf_updateNavigationBar(removeUnderline: true)
        self.updateSearchButton()
    }
    
    private func settingsBarButtonItem() -> UIBarButtonItem {
        return UIBarButtonItem(image: #imageLiteral(resourceName: "settings"), style: .plain, target: self, action: #selector(didTapSettingsButton(_:)))
    }
    
    public func didTapSettingsButton(_ sender: UIBarButtonItem) {
        showSettings()
    }
    
    private func updateSearchButton() {
        let extNavBarHeight = extendedNavBarView.frame.size.height
        let extNavBarOffset = abs(extendNavBarViewTopSpaceConstraint.constant)
        self.searchBarButtonItem?.alpha = extNavBarOffset / extNavBarHeight
    }
    
    // MARK: - Actions
    
    public func showSettings() {
        let settingsContainer = UINavigationController(rootViewController: WMFSettingsViewController.init(dataStore: self.userStore))
        present(settingsContainer, animated: true, completion: nil)
    }
    
    public func titleBarButtonPressed() {
        self.collectionViewController.collectionView?.setContentOffset(CGPoint.zero, animated: true)
    }
    
    // MARK: - WMFExploreCollectionViewControllerDelegate
    
    func exploreCollectionViewController(_ collectionVC: WMFExploreCollectionViewController, didScroll scrollView: UIScrollView) {
        //DDLogDebug("scrolled! \(scrollView.contentOffset)")
        
        guard self.view != nil else {
            // view not loaded yet
            return
        }
        
        let extNavBarHeight = extendedNavBarView.frame.size.height
        let extNavBarOffset = abs(extendNavBarViewTopSpaceConstraint.constant)
        let scrollY = scrollView.contentOffset.y
        
        // no change in scrollY
        if (scrollY == 0) {
            //DDLogDebug("no change in scroll")
            return
        }

        // pulling down when nav bar is already extended
        if (extNavBarOffset == 0 && scrollY < 0) {
            //DDLogDebug("  bar already extended")
            return
        }
        
        // pulling up when navbar isn't fully collapsed
        if (extNavBarOffset == extNavBarHeight && scrollY > 0) {
            //DDLogDebug("  bar already collapsed")
            return
        }
        
        let newOffset: CGFloat
        
        // pulling down when nav bar is partially hidden
        if (scrollY < 0) {
            newOffset = max(extNavBarOffset - abs(scrollY), 0)
            //DDLogDebug("  showing bar newOffset:\(newOffset)")

        // pulling up when navbar isn't fully collapsed
        } else {
            newOffset = min(extNavBarOffset + abs(scrollY), extNavBarHeight)
            //DDLogDebug("  hiding bar newOffset:\(newOffset)")
        }

        extendNavBarViewTopSpaceConstraint.constant = -newOffset
        
        self.updateSearchButton()
        
        scrollView.contentOffset = CGPoint(x: 0, y: 0)
    }
    
    func exploreCollectionViewController(_ collectionVC: WMFExploreCollectionViewController, didEndScrolling scrollView: UIScrollView) {

        let extNavBarHeight = extendedNavBarView.frame.size.height
        let extNavBarOffset = abs(extendNavBarViewTopSpaceConstraint.constant)

        var newOffset: CGFloat?
        if (extNavBarOffset > 0 && extNavBarOffset <= extNavBarHeight/2) {
            DDLogDebug("Need to scroll down")
            newOffset = 0
        } else if (extNavBarOffset > extNavBarHeight/2 && extNavBarOffset < extNavBarHeight) {
            DDLogDebug("Need to scroll up")
            newOffset = extNavBarHeight
        }

        if (newOffset != nil) {
            let newAlpha: CGFloat = newOffset == 0 ? 0 : 1
            self.view.layoutIfNeeded() // Apple recommends you call layoutIfNeeded before the animation block ensure all pending layout changes are applied
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: {
                self.extendNavBarViewTopSpaceConstraint.constant = -newOffset!
                self.searchBarButtonItem?.alpha = newAlpha
                self.view.layoutIfNeeded() // layoutIfNeeded must be called from within the animation block
            });
        }
    }
    
    // MARK: - UISearchBarDelegate
    
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        self.wmf_showSearch(animated: true)
        return false
    }
    
    // MARK: - Analytics
    
    public var analyticsContext: String {
        return "Explore"
    }
    
    public var analyticsName: String {
        return analyticsContext
    }
    
    // MARK: -
    
    @objc(updateFeedSourcesUserInitiated:)
    public func updateFeedSources(userInitiated wasUserInitiated: Bool) {
        self.collectionViewController.updateFeedSourcesUserInitiated(wasUserInitiated)
    }
    
    @objc(showInTheNewsForStory:date:animated:)
    public func showInTheNews(for story: WMFFeedNewsStory, date: Date?, animated: Bool)
    {
        self.collectionViewController.showInTheNews(for: story, date: date, animated: animated)
    }
    
    @objc(presentMoreViewControllerForGroup:animated:)
    public func presentMoreViewController(for group: WMFContentGroup, animated: Bool)
    {
        self.collectionViewController.presentMoreViewController(for: group, animated: animated)
    }
}
