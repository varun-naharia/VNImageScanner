//
//  ViewController.swift
//  VNImageScanner
//
//  Created by Varun Naharia on 11/04/17.
//  Copyright © 2017 Varun. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var cameraViewController: VNCameraScanner!
    @IBOutlet weak var focusIndicator: UIImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        cameraViewController.setupCameraView()
        cameraViewController.isEnableBorderDetection = true
        updateTitleLabel()

    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        cameraViewController.start()
    }
    
    @IBAction func focusGesture(_ sender: UITapGestureRecognizer) {
        if sender.state == UIGestureRecognizerState.recognized {
            let location: CGPoint = sender.location(in: self.cameraViewController)
            focusIndicatorAnimate(to: location)
            cameraViewController.focus(at: location, completionHandler: {() -> Void in
                self.focusIndicatorAnimate(to: location)
            })
        }
    }
    
    func focusIndicatorAnimate(to targetPoint: CGPoint) {
        focusIndicator.center = targetPoint
        focusIndicator.alpha = 0.0
        focusIndicator.isHidden = false
        UIView.animate(withDuration: 0.4, animations: {() -> Void in
            self.focusIndicator.alpha = 1.0
        }, completion: {(_ finished: Bool) -> Void in
            UIView.animate(withDuration: 0.4, animations: {() -> Void in
                self.focusIndicator.alpha = 0.0
            })
        })
    }
    
    func change(_ button: UIButton, targetTitle title: String, toStateEnabled enabled: Bool) {
        button.setTitle(title, for: .normal)
        button.setTitleColor((enabled) ? UIColor(red: CGFloat(1), green: CGFloat(0.81), blue: CGFloat(0), alpha: CGFloat(1)) : UIColor.white, for: .normal)
    }
    
    @IBAction func borderDetectToggle(_ sender: UIButton) {
        let enable: Bool = !cameraViewController.isEnableBorderDetection
        change(sender, targetTitle: (enable) ? "CROP On" : "CROP Off", toStateEnabled: enable)
        cameraViewController.isEnableBorderDetection = enable
        updateTitleLabel()
    }
    
    @IBAction func filterToggle(_ sender: Any) {
        cameraViewController.cameraViewType = (cameraViewController.cameraViewType == VNCameraViewType.blackAndWhite) ? VNCameraViewType.normal : VNCameraViewType.blackAndWhite
        updateTitleLabel()
    }
    
    @IBAction func torchToggle(_ sender: UIButton) {
        let enable: Bool = !cameraViewController.isEnableTorch
        change(sender, targetTitle: (enable) ? "FLASH On" : "FLASH Off", toStateEnabled: enable)
        cameraViewController.isEnableTorch = enable
    }
    
    func updateTitleLabel() {
        
//        let animation = CATransition.animation()
        let animation:CATransition = CATransition()
        animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseOut)
        animation.type = kCATransitionPush
        animation.subtype = kCATransitionFromBottom
        animation.duration = 0.35
        titleLabel?.layer.add(animation, forKey: "kCATransitionFade")
        let filterMode: String = (cameraViewController.cameraViewType == VNCameraViewType.blackAndWhite) ? "TEXT FILTER" : "COLOR FILTER"
        titleLabel?.text = filterMode + (" | \((cameraViewController.isEnableBorderDetection) ? "AUTOCROP On" : "AUTOCROP Off")")
    }
    
    @IBAction func captureButton(_ sender: Any) {
        weak var weakSelf = self
        cameraViewController.captureImage(withCompletionHander: {(_ imageFilePath: String) -> Void in
            let captureImageView = UIImageView(image: UIImage(contentsOfFile: imageFilePath))
            captureImageView.backgroundColor = UIColor(white: CGFloat(0.0), alpha: CGFloat(0.7))
            captureImageView.frame = (weakSelf?.view.bounds.offsetBy(dx: CGFloat(0), dy: CGFloat((weakSelf?.view.bounds.size.height)!)))!
            captureImageView.alpha = 1.0
            captureImageView.contentMode = .scaleAspectFit
            captureImageView.isUserInteractionEnabled = true
            weakSelf?.view.addSubview(captureImageView)
            let dismissTap = UITapGestureRecognizer(target: weakSelf, action: #selector(self.dismissPreview))
            captureImageView.addGestureRecognizer(dismissTap)
            UIView.animate(withDuration: 0.7, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.7, options: .allowUserInteraction, animations: {() -> Void in
                captureImageView.frame = (weakSelf?.view.bounds)!
            }, completion: { _ in })
        })
    }
    
    func dismissPreview(_ dismissTap: UITapGestureRecognizer) {
        UIView.animate(withDuration: 0.7, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 1.0, options: .allowUserInteraction, animations: {() -> Void in
            dismissTap.view?.frame = self.view.bounds.offsetBy(dx: CGFloat(0), dy: CGFloat(self.view.bounds.size.height))
        }, completion: {(_ finished: Bool) -> Void in
            dismissTap.view?.removeFromSuperview()
        })
    }


}

