//
//  PhotoCollectionViewLayout.swift
//  Finjinon
//
//  Created by Sørensen, Johan on 22.06.15.
//  Copyright (c) 2015 FINN.no AS. All rights reserved.
//

import UIKit

private class DraggingProxy: UIImageView {
    var dragIndexPath: NSIndexPath? // Current indexPath
    var dragCenter = CGPoint.zeroPoint // point being dragged from
    var fromIndexPath: NSIndexPath? // Original index path
    var toIndexPath: NSIndexPath? // index path the proxy was dragged to
    var initialCenter = CGPoint.zeroPoint

    init(cell: UICollectionViewCell) {
        super.init(frame: CGRect.zeroRect)

        UIGraphicsBeginImageContextWithOptions(cell.bounds.size, false, 0)
        cell.drawViewHierarchyInRect(cell.bounds, afterScreenUpdates: true)
        let cellImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        image = cellImage
        frame = CGRect(x: 0, y: 0, width: cell.bounds.width, height: cell.bounds.height)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public protocol PhotoCollectionViewLayoutDelegate: NSObjectProtocol {
    func photoCollectionViewLayout(layout: UICollectionViewLayout, canMoveItemAtIndexPath indexPath: NSIndexPath) -> Bool
}

internal class PhotoCollectionViewLayout: UICollectionViewFlowLayout, UIGestureRecognizerDelegate {
    internal var didReorderHandler: (fromIndexPath: NSIndexPath, toIndexPath: NSIndexPath) -> Void = { (_,_) in }
    private var insertedIndexPaths: [NSIndexPath] = []
    private var deletedIndexPaths: [NSIndexPath] = []
    private var longPressGestureRecognizer: UILongPressGestureRecognizer!
    private var panGestureRecgonizer: UIPanGestureRecognizer!
    private var dragProxy: DraggingProxy?
    internal weak var delegate: PhotoCollectionViewLayoutDelegate?

    override init() {
        super.init()
        self.addObserver(self, forKeyPath: "collectionView", options: nil, context: nil)
    }

    required init(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.addObserver(self, forKeyPath: "collectionView", options: nil, context: nil)
    }

    deinit {
        self.removeObserver(self, forKeyPath: "collectionView", context: nil)
    }

    override func observeValueForKeyPath(keyPath: String, ofObject object: AnyObject, change: [NSObject : AnyObject], context: UnsafeMutablePointer<Void>) {
        if keyPath == "collectionView" {
            setupGestureRecognizers()
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }

    // MARK: - UICollectionView

    override func prepareForCollectionViewUpdates(updateItems: [AnyObject]!) {
        super.prepareForCollectionViewUpdates(updateItems)

        insertedIndexPaths.removeAll(keepCapacity: false)
        deletedIndexPaths.removeAll(keepCapacity: false)

        for update in updateItems as! [UICollectionViewUpdateItem] {
            switch update.updateAction {
            case .Insert:
                insertedIndexPaths.append(update.indexPathAfterUpdate!)
            case .Delete:
                deletedIndexPaths.append(update.indexPathBeforeUpdate!)
            default:
                return
            }
        }
    }

    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()

        insertedIndexPaths.removeAll(keepCapacity: false)
        deletedIndexPaths.removeAll(keepCapacity: false)
    }

    override func initialLayoutAttributesForAppearingItemAtIndexPath(itemIndexPath: NSIndexPath) -> UICollectionViewLayoutAttributes? {
        let attrs = super.initialLayoutAttributesForAppearingItemAtIndexPath(itemIndexPath)

        if contains(insertedIndexPaths, itemIndexPath) {
            // only change attributes on inserted cells
            if let attrs = attrs {
                attrs.alpha = 0.0
                attrs.center.x = -(attrs.frame.width + minimumInteritemSpacing)
                attrs.center.y = self.collectionView!.frame.height / 2
                attrs.transform3D = scaledTransform3DForLayoutAttribute(attrs, scale: 0.001)
            }
        }

        return attrs
    }

    override func finalLayoutAttributesForDisappearingItemAtIndexPath(itemIndexPath: NSIndexPath) -> UICollectionViewLayoutAttributes? {
        let attrs = super.finalLayoutAttributesForDisappearingItemAtIndexPath(itemIndexPath)

        if contains(deletedIndexPaths, itemIndexPath) {
            if let attrs = attrs {
                attrs.alpha = 0.0
                attrs.center.x = self.collectionView!.frame.width / 2
                attrs.center.y = self.collectionView!.frame.height + minimumLineSpacing
                attrs.transform3D = scaledTransform3DForLayoutAttribute(attrs, scale: 0.001)
            }
        }

        return attrs
    }

    private func scaledTransform3DForLayoutAttribute(attributes: UICollectionViewLayoutAttributes,scale: CGFloat) -> CATransform3D {
        let transform = CATransform3DTranslate(attributes.transform3D, attributes.frame.midX - self.collectionView!.frame.midX, attributes.frame.midY - self.collectionView!.frame.midY, 0)
        return CATransform3DScale(transform, scale, scale, 1)
    }

    override func layoutAttributesForElementsInRect(rect: CGRect) -> [AnyObject]? {
        if let attributes = super.layoutAttributesForElementsInRect(rect) as? [UICollectionViewLayoutAttributes] {
            for layoutAttribute in attributes {
                if layoutAttribute.representedElementCategory != .Cell {
                    continue
                }

                if layoutAttribute.indexPath == dragProxy?.dragIndexPath {
                    layoutAttribute.alpha = 0.0 // hide the sourceCell, the drag proxy now represents it
                }
            }

            return attributes
        }
        return nil
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == longPressGestureRecognizer && otherGestureRecognizer == panGestureRecgonizer {
            return true
        } else if gestureRecognizer == panGestureRecgonizer {
            return otherGestureRecognizer == longPressGestureRecognizer
        }

        return true
    }

    func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
        func canMoveItemAtIndexPath(indexPath: NSIndexPath) -> Bool {
            return delegate?.photoCollectionViewLayout(self, canMoveItemAtIndexPath: indexPath) ?? true
        }

        if gestureRecognizer == longPressGestureRecognizer {
            let location = gestureRecognizer.locationInView(collectionView)
            if let indexPath = collectionView?.indexPathForItemAtPoint(location) where !canMoveItemAtIndexPath(indexPath) {
                return false
            }
        }

        let states: [UIGestureRecognizerState] = [.Possible, .Failed]
        if gestureRecognizer == longPressGestureRecognizer && !contains(states, collectionView!.panGestureRecognizer.state) {
            return false
        } else if gestureRecognizer == panGestureRecgonizer && contains(states, longPressGestureRecognizer.state) {
            return false
        }

        return true
    }

    // MARK: -  Private methods

    func handleLongPressGestureRecognized(recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .Began:
            let location = recognizer.locationInView(collectionView)
            if let indexPath = collectionView!.indexPathForItemAtPoint(location), let cell = collectionView!.cellForItemAtIndexPath(indexPath) {
                let proxy = DraggingProxy(cell: cell)
                proxy.dragIndexPath = indexPath
                proxy.frame = cell.bounds
                proxy.initialCenter = cell.center
                proxy.dragCenter = cell.center
                proxy.center = proxy.dragCenter

                proxy.fromIndexPath = indexPath

                dragProxy = proxy
                collectionView?.addSubview(proxy)

                invalidateLayout()

                UIView.animateWithDuration(0.16, animations: {
                    self.dragProxy?.transform = CGAffineTransformMakeScale(1.1, 1.1)
                })
            }
        case .Ended:
            if let proxy = self.dragProxy {
                UIView.animateWithDuration(0.2, delay: 0.0, options: .BeginFromCurrentState | .CurveEaseIn, animations: {
                    proxy.center = proxy.dragCenter
                    proxy.transform = CGAffineTransformIdentity
                }, completion: { finished in
                    proxy.removeFromSuperview()

                    if let fromIndexPath = proxy.fromIndexPath, let toIndexPath = proxy.toIndexPath {
                        self.didReorderHandler(fromIndexPath: fromIndexPath, toIndexPath: toIndexPath)
                    }

                    self.dragProxy = nil

                    self.invalidateLayout()
                })
            }
        default:
            break
        }
    }

    func handlePanGestureRecognized(recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translationInView(collectionView!)
        switch recognizer.state {
        case .Changed:
            if let proxy = dragProxy {
                proxy.center.x = proxy.initialCenter.x + translation.x
                //TODO: Constrain to be within collectionView.frame:
                // proxy.center.y = proxy.originalCenter.y + translation.y

                if let fromIndexPath = proxy.dragIndexPath, let toIndexPath = collectionView!.indexPathForItemAtPoint(proxy.center) {
                    let targetLayoutAttributes = layoutAttributesForItemAtIndexPath(toIndexPath)
                    proxy.dragIndexPath = toIndexPath
                    proxy.dragCenter = targetLayoutAttributes.center
                    proxy.bounds = targetLayoutAttributes.bounds
                    proxy.toIndexPath = toIndexPath

                    collectionView?.performBatchUpdates({
                        self.collectionView?.moveItemAtIndexPath(fromIndexPath, toIndexPath: toIndexPath)
                    }, completion: nil)
                }
            }
        default:
            break
        }
    }

    private func setupGestureRecognizers() {
        if let collectionView = self.collectionView {
            longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: Selector("handleLongPressGestureRecognized:"))
            longPressGestureRecognizer.delegate = self

            panGestureRecgonizer = UIPanGestureRecognizer(target: self, action: Selector("handlePanGestureRecognized:"))
            panGestureRecgonizer.delegate = self
            panGestureRecgonizer.maximumNumberOfTouches = 1

            collectionView.addGestureRecognizer(longPressGestureRecognizer)
            collectionView.addGestureRecognizer(panGestureRecgonizer)
        }
    }
}
