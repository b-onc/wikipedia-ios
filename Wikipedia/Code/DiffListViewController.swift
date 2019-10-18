
import UIKit

protocol DiffListDelegate: class {
    func diffListScrollViewDidScroll(_ scrollView: UIScrollView)
}

class DiffListViewController: ViewController {
    
    enum ListUpdateType {
        case itemExpandUpdate(indexPath: IndexPath) //tapped context cell to expand
        case layoutUpdate(collectionViewWidth: CGFloat, traitCollection: UITraitCollection) //willTransitionToSize - simple rotation that keeps size class
        case initialLoad(width: CGFloat)
        case theme(theme: Theme)
    }

    lazy private(set) var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.contentInsetAdjustmentBehavior = .never
        scrollView = collectionView
        return collectionView
    }()
    
    private var dataSource: [DiffListGroupViewModel] = []
    private weak var delegate: DiffListDelegate?

    private var updateWidthsOnLayoutSubviews = false
    private var isRotating = false
    
    private var centerIndexPath: IndexPath? {
        let center = view.convert(collectionView.center, to: collectionView)
        return collectionView.indexPathForItem(at: center)
    }
    private var indexPathBeforeRotating: IndexPath?
    private let chunkedHeightCalculationsConcurrentQueue = DispatchQueue(label: "com.wikipedia.diff.chunkedHeightCalculations", qos: .userInteractive, attributes: .concurrent)
    private let layoutSubviewsHeightCalculationsSerialQueue = DispatchQueue(label: "com.wikipedia.diff.layoutHeightCalculations", qos: .userInteractive)
    
    init(theme: Theme, delegate: DiffListDelegate?) {
        super.init(nibName: nil, bundle: nil)
        self.theme = theme
        self.delegate = delegate
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addConstraints([
            view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            view.topAnchor.constraint(equalTo: collectionView.topAnchor),
            view.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor)
        ])
        collectionView.register(DiffListChangeCell.wmf_classNib(), forCellWithReuseIdentifier: DiffListChangeCell.reuseIdentifier)
        collectionView.register(DiffListContextCell.wmf_classNib(), forCellWithReuseIdentifier: DiffListContextCell.reuseIdentifier)
        collectionView.register(DiffListUneditedCell.wmf_classNib(), forCellWithReuseIdentifier: DiffListUneditedCell.reuseIdentifier)
    }
    
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            
            if updateWidthsOnLayoutSubviews {
                
                //possibly overkill...simple main thread way to do this is updateListViewModels(listViewModel: self.dataSource, updateType: updateType) followed by the main thread lines 78-83. This does seem very slightly faster for rotation though, and could yield more gains as diffs get larger. More improvements could be size caching & putting layoutSubviewsHeightCalculationsSerialQueue instead into an NSOperation to be cancelled if another viewDidLayoutSubviews is called. No need to continue calculating sizes if collection view frame has changed again.
                //todo: clean up - move this and updateListViewModel methods into separate class, DiffListSizeCalculator or something
                let updateType = ListUpdateType.layoutUpdate(collectionViewWidth: self.collectionView.frame.width, traitCollection: self.traitCollection)
                
                //actually not sure if this serial queue is needed or simply calling on the main thread (also serial) is the same. this also seems faster than without though.
                layoutSubviewsHeightCalculationsSerialQueue.async {
                    
                    self.backgroundUpdateListViewModels(listViewModel: self.dataSource, updateType: updateType) {
                        
                        DispatchQueue.main.async {
                            self.applyListViewModelChanges(updateType: updateType)
                            
                            if let indexPathBeforeRotating = self.indexPathBeforeRotating {
                                self.collectionView.scrollToItem(at: indexPathBeforeRotating, at: .centeredVertically, animated: false)
                                self.indexPathBeforeRotating = nil
                            }
                        }
                        
                    }
                }
            }
        }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        updateWidthsOnLayoutSubviews = true
        isRotating = true
        
        self.indexPathBeforeRotating = centerIndexPath
        coordinator.animate(alongsideTransition: { (context) in
            
            //nothing
            
        }) { (context) in
            self.updateWidthsOnLayoutSubviews = false
            self.isRotating = false
        }

    }
    
    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)
        
        updateWidthsOnLayoutSubviews = true
        coordinator.animate(alongsideTransition: { (context) in
        }) { (context) in
            self.updateWidthsOnLayoutSubviews = false
        }
        
    }
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        super.scrollViewDidScroll(scrollView)
        delegate?.diffListScrollViewDidScroll(scrollView)
    }
    
    func updateListViewModels(listViewModel: [DiffListGroupViewModel], updateType: DiffListViewController.ListUpdateType) {
        
        switch updateType {
        case .itemExpandUpdate(let indexPath):
            
            if let item = listViewModel[safeIndex: indexPath.item] as? DiffListContextViewModel {
                item.isExpanded.toggle()
            }
            
        case .layoutUpdate(let width, let traitCollection):
            for item in listViewModel {
                if item.width != width || item.traitCollection != traitCollection {
                    item.updateSize(width: width, traitCollection: traitCollection)
                }
            }
        
        case .initialLoad(let width):
            for var item in listViewModel {
                if item.width != width {
                    item.width = width
                }
            }
            self.dataSource = listViewModel
        case .theme(let theme):
            for var item in listViewModel {
                if item.theme != theme {
                    item.theme = theme
                }
            }
        }
    }
    
        func backgroundUpdateListViewModels(listViewModel: [DiffListGroupViewModel], updateType: DiffListViewController.ListUpdateType, completion: @escaping () -> Void) {
    
            let group = DispatchGroup()
    
            let chunked = listViewModel.chunked(into: 10)
    
            for chunk in chunked {
                chunkedHeightCalculationsConcurrentQueue.async(group: group) {
                    
                    self.updateListViewModels(listViewModel: chunk, updateType: updateType)
                }
            }
    
            group.notify(queue: layoutSubviewsHeightCalculationsSerialQueue) {
                completion()
            }
        }
    
    func applyListViewModelChanges(updateType: DiffListViewController.ListUpdateType) {
        switch updateType {
        case .itemExpandUpdate:
            
            collectionView.setCollectionViewLayout(UICollectionViewFlowLayout(), animated: true)
 
        default:
            collectionView.reloadData()
        }
    }
    
    override func apply(theme: Theme) {
        
        guard isViewLoaded else {
            return
        }
        
        super.apply(theme: theme)
        
        updateListViewModels(listViewModel: dataSource, updateType: .theme(theme: theme))

        collectionView.backgroundColor = theme.colors.paperBackground
    }
}

extension DiffListViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataSource.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        guard let viewModel = dataSource[safeIndex: indexPath.item] else {
            return UICollectionViewCell()
        }
        
        //tonitodo: clean up
        
        if let viewModel = viewModel as? DiffListChangeViewModel,
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiffListChangeCell.reuseIdentifier, for: indexPath) as? DiffListChangeCell {
            cell.update(viewModel)
            return cell
        } else if let viewModel = viewModel as? DiffListContextViewModel,
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiffListContextCell.reuseIdentifier, for: indexPath) as? DiffListContextCell {
            cell.update(viewModel, indexPath: indexPath)
            cell.delegate = self
            return cell
        } else if let viewModel = viewModel as? DiffListUneditedViewModel,
           let cell = collectionView.dequeueReusableCell(withReuseIdentifier: DiffListUneditedCell.reuseIdentifier, for: indexPath) as? DiffListUneditedCell {
           cell.update(viewModel)
           return cell
        }
        
        return UICollectionViewCell()
    }
}

extension DiffListViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        guard let viewModel = dataSource[safeIndex: indexPath.item] else {
            return .zero
        }
        
        if let contextViewModel = viewModel as? DiffListContextViewModel {
            let height = contextViewModel.isExpanded ? contextViewModel.expandedHeight : contextViewModel.height
            return CGSize(width: min(collectionView.frame.width, contextViewModel.width), height: height)
        }
        
        return CGSize(width: min(collectionView.frame.width, viewModel.width), height: viewModel.height)

    }
    
    func collectionView(_ collectionView: UICollectionView, targetContentOffsetForProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        
        if !isRotating {
            //prevents jumping when expanding/collapsing context cell
            return collectionView.contentOffset
        } else {
            return proposedContentOffset
        }
        
    }
}

extension DiffListViewController: DiffListContextCellDelegate {
    func didTapContextExpand(indexPath: IndexPath) {
        
        updateListViewModels(listViewModel: dataSource, updateType: .itemExpandUpdate(indexPath: indexPath))
        applyListViewModelChanges(updateType: .itemExpandUpdate(indexPath: indexPath))
        
        if let contextViewModel = dataSource[safeIndex: indexPath.item] as? DiffListContextViewModel,
        let cell = collectionView.cellForItem(at: indexPath) as? DiffListContextCell {
            cell.update(contextViewModel, indexPath: indexPath)
        }
    }
}
