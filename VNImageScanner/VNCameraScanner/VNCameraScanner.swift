//
//  VNCameraScanner.swift
//  VNImageScanner
//
//  Created by Varun Naharia on 11/04/17.
//  Copyright © 2017 Varun. All rights reserved.
//

import UIKit
import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore
import CoreImage
import ImageIO
import MobileCoreServices
import GLKit
import OpenGLES

enum VNCameraViewType : Int {
    case blackAndWhite
    case normal
}

class VNRectangleFeature: CIFeature {
    open var topLeft = CGPoint.zero
    open var topRight = CGPoint.zero
    open var bottomRight = CGPoint.zero
    open var bottomLeft = CGPoint.zero
    
    
    class func setValue(topLeft:CGPoint, topRight:CGPoint, bottomLeft:CGPoint, bottomRight:CGPoint) -> VNRectangleFeature {
        let obj:VNRectangleFeature = VNRectangleFeature()
        obj.topLeft = topLeft
        obj.topRight = topRight
        obj.bottomLeft = bottomLeft
        obj.bottomRight = bottomLeft
        return obj
    }
}
class VNCameraScanner:UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    var captureSession: AVCaptureSession?
    var captureDevice: AVCaptureDevice?
    var context: EAGLContext?
    var stillImageOutput: AVCaptureStillImageOutput?
    var isForceStop: Bool = false
    private var _intrinsicContentSize:CGSize = CGSize(width: 0, height: 0)
    override var intrinsicContentSize: CGSize {
        get {
            //...
            return _intrinsicContentSize
        }
        set {
            
            _intrinsicContentSize = newValue
        }
        
    }
    var coreImageContext: CIContext?
    var renderBuffer = GLuint()
    var glkView: GLKView?
    var isStopped: Bool = false
    var imageDedectionConfidence: CGFloat = 0.0
    var borderDetectTimeKeeper: Timer?
    var borderDetectFrame: Bool = false
    var borderDetectLastRectangleFeature: VNRectangleFeature?
    var isCapturing: Bool = false
    var captureQueue:DispatchQueue!
    var cameraViewType:VNCameraViewType!
    var isEnableBorderDetection: Bool = false
    var isEnableTorch: Bool = false
    
    override func awakeFromNib() {
        super.awakeFromNib()
        NotificationCenter.default.addObserver(self, selector: #selector(self._backgroundMode), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self._foregroundMode), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        captureQueue = DispatchQueue(label: "com.instapdf.AVCameraCaptureQueue")
    }
    
    func _backgroundMode() {
        isForceStop = true
    }
    
    func _foregroundMode() {
        isForceStop = false
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func createGLKView() {
        if (context != nil) {
            return
        }
        context = EAGLContext(api: EAGLRenderingAPI.openGLES2)
        let view = GLKView(frame: bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.translatesAutoresizingMaskIntoConstraints = true
        view.context = context!
        view.contentScaleFactor = 1.0
        view.drawableDepthFormat = GLKViewDrawableDepthFormat.format24
        insertSubview(view, at: 0)
        glkView = view
        coreImageContext = CIContext(eaglContext: context!, options: [kCIContextWorkingColorSpace: NSNull(), kCIContextUseSoftwareRenderer: (false)])
    }
    func setupCameraView() {
        createGLKView()
        let possibleDevices: [Any] = AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo)
        let device: AVCaptureDevice? = possibleDevices.first as! AVCaptureDevice?
        if device == nil {
            return
        }
        imageDedectionConfidence = 0.0
        let session = AVCaptureSession()
        captureSession = session
        session.beginConfiguration()
        captureDevice = device
        var error: Error? = nil
        let input = try? AVCaptureDeviceInput(device: device)
        session.sessionPreset = AVCaptureSessionPresetPhoto
        session.addInput(input)
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.alwaysDiscardsLateVideoFrames = true
        dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable: kCVPixelFormatType_32BGRA]
        dataOutput.setSampleBufferDelegate(self, queue: captureQueue)
        session.addOutput(dataOutput)
        
        stillImageOutput = AVCaptureStillImageOutput()
        session.addOutput(stillImageOutput)
        let connection: AVCaptureConnection? = dataOutput.connections.first as! AVCaptureConnection?
        connection?.videoOrientation = .portrait
        if (device?.isFlashAvailable)! {
            do{
               try  device?.lockForConfiguration()
            }
            catch
            {
                
            }
            device?.flashMode = .off
            device?.unlockForConfiguration()
            if (device?.isFocusModeSupported(.continuousAutoFocus))! {
                do{
                    try  device?.lockForConfiguration()
                }
                catch
                {
                    
                }
                device?.focusMode = .continuousAutoFocus
                device?.unlockForConfiguration()
            }
        }
        session.commitConfiguration()
    }
    
    func setCameraViewType(_ cameraViewType: VNCameraViewType) {
        let effect = UIBlurEffect(style: .dark)
        let viewWithBlurredBackground = UIVisualEffectView(effect: effect)
        viewWithBlurredBackground.frame = bounds
        insertSubview(viewWithBlurredBackground, aboveSubview: glkView!)
        self.cameraViewType = cameraViewType
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(0.3 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: {() -> Void in
            viewWithBlurredBackground.removeFromSuperview()
        })
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutputSampleBuffer sampleBuffer: CMSampleBuffer?, from connection: AVCaptureConnection) {
        
        if isForceStop {
            return
        }
        if isStopped || isCapturing || !CMSampleBufferIsValid(sampleBuffer!) {
            return
        }
        let pixelBuffer: CVPixelBuffer? = CMSampleBufferGetImageBuffer(sampleBuffer!)!
        var image = CIImage(cvPixelBuffer: pixelBuffer!)
        if cameraViewType != VNCameraViewType.normal {
            image = filteredImageUsingEnhanceFilter(on: image)
        }
        else {
            image = filteredImageUsingContrastFilter(on: image)
        }
        if isEnableBorderDetection {
            if borderDetectFrame {
                borderDetectLastRectangleFeature = biggestRectangle(inRectangles: (highAccuracyRectangleDetector()?.features(in: image))!)
                borderDetectFrame = false
            }
            if (borderDetectLastRectangleFeature?.bottomLeft != nil) {
                imageDedectionConfidence += 0.5
                image = drawHighlightOverlay(forPoints: image, topLeft: (borderDetectLastRectangleFeature?.topLeft)!, topRight: (borderDetectLastRectangleFeature?.topRight)!, bottomLeft: (borderDetectLastRectangleFeature?.bottomLeft)!, bottomRight: (borderDetectLastRectangleFeature?.bottomRight)!)
            }
            else {
                imageDedectionConfidence = 0.0
            }
        }
        if ((self.context != nil) && (coreImageContext != nil))
        {
            if(context != EAGLContext.current())
            {
                EAGLContext.setCurrent(context)
            }
            glkView?.bindDrawable()
            coreImageContext?.draw(image, in: self.bounds, from: self.cropRect(forPreviewImage: image))
            glkView?.display()
            
            if(intrinsicContentSize.width != image.extent.size.width) {
                self.intrinsicContentSize = image.extent.size;
                DispatchQueue.main.async {
                    self.invalidateIntrinsicContentSize()
                }
            }
            
            image = CIImage();
        }
    }
    
    func filteredImageUsingEnhanceFilter(on image: CIImage) -> CIImage {
        return (CIFilter(name: "CIColorControls", withInputParameters: [kCIInputImageKey:image, "inputBrightness": NSNumber(value: 0.0), "inputContrast":NSNumber(value: 1.14), "inputSaturation": NSNumber(value: 0.0)])?.outputImage)!
    }
    
    func filteredImageUsingContrastFilter(on image: CIImage) -> CIImage {
        return CIFilter(name: "CIColorControls", withInputParameters: ["inputContrast": (1.1), kCIInputImageKey: image])!.outputImage!
    }
    
    func _biggestRectangle(inRectangles rectangles: [Any]) -> CIRectangleFeature? {
        if !(rectangles.count > 0){
            return nil
        }
        var halfPerimiterValue: Float = 0
        var biggestRectangle: CIRectangleFeature = rectangles.first as! CIRectangleFeature
        for rect: CIRectangleFeature in rectangles as! [CIRectangleFeature] {
            let p1: CGPoint = rect.topLeft
            let p2: CGPoint = rect.topRight
            let width: CGFloat = CGFloat(hypotf(Float(p1.x) - Float(p2.x), Float(p1.y) - Float(p2.y)))
            let p3: CGPoint = rect.topLeft
            let p4: CGPoint = rect.bottomLeft
            let height: CGFloat = CGFloat(hypotf(Float(p3.x) - Float(p4.x), Float(p3.y) - Float(p4.y)))
            let currentHalfPerimiterValue: CGFloat = height + width
            if halfPerimiterValue < Float(currentHalfPerimiterValue) {
                halfPerimiterValue = Float(currentHalfPerimiterValue)
                biggestRectangle = rect
            }
        }
        return biggestRectangle
    }
    
    func biggestRectangle(inRectangles rectangles: [Any]) -> VNRectangleFeature? {
        let rectangleFeature: CIRectangleFeature? = _biggestRectangle(inRectangles: rectangles)
        if rectangleFeature == nil {
            return nil
        }
        // Credit: http://stackoverflow.com/a/20399468/1091044
        //         http://stackoverflow.com/questions/42474408/
        let points = [
            rectangleFeature?.topLeft,
            rectangleFeature?.topRight,
            rectangleFeature?.bottomLeft,
            rectangleFeature?.bottomRight
        ]
        
        var minimum = points[0]
        var maximum = points[0]
        for point in points {
            minimum?.x = min((minimum?.x)!, (point?.x)!)
            minimum?.y = min((minimum?.y)!, (point?.y)!)
            maximum?.x = max((maximum?.x)!, (point?.x)!)
            maximum?.y = max((maximum?.y)!, (point?.y)!)
        }
        let center = CGPoint(x: ((minimum?.x)! + (maximum?.x)!) / 2, y: ((minimum?.y)! + (maximum?.y)!) / 2)
        let angle = { (point: CGPoint) -> CGFloat in
            let theta = atan2(point.y - center.y, point.x - center.x)
            return fmod(.pi * 3.0 / 4.0 + theta, 2 * .pi)
        }
        let sortedPoints = points.sorted{angle($0!) < angle($1!)}
        let rectangleFeatureMutable = VNRectangleFeature()
        rectangleFeatureMutable.topLeft = sortedPoints[3]!
        rectangleFeatureMutable.topRight = sortedPoints[2]!
        rectangleFeatureMutable.bottomRight = sortedPoints[1]!
        rectangleFeatureMutable.bottomLeft = sortedPoints[0]!
        return rectangleFeatureMutable
    }
    
    func highAccuracyRectangleDetector() -> CIDetector? {
        var detector: CIDetector? = nil
            detector = CIDetector.init(ofType: CIDetectorTypeRectangle, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return detector!
    }
    
    func drawHighlightOverlay(forPoints image: CIImage, topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) -> CIImage {
        var overlay = CIImage(color: CIColor(red: CGFloat(1), green: CGFloat(0), blue: CGFloat(0), alpha: CGFloat(0.6)))
        overlay = overlay.cropping(to: image.extent)
        overlay = overlay.applyingFilter("CIPerspectiveTransformWithExtent", withInputParameters: ["inputExtent": CIVector(cgRect: image.extent), "inputTopLeft": CIVector(cgPoint: topLeft), "inputTopRight": CIVector(cgPoint:topRight), "inputBottomLeft": CIVector(cgPoint:bottomLeft), "inputBottomRight": CIVector(cgPoint:bottomRight)]) //applyingFilter("CIPerspectiveTransformWithExtent", withInputParameters: ["inputExtent": CIVector(cgRect: image.extent()), "inputTopLeft": CIVector(topLeft), "inputTopRight": CIVector(topRight), "inputBottomLeft": CIVector(bottomLeft), "inputBottomRight": CIVector(bottomRight)])
        return overlay.compositingOverImage(image)
    }
    
    func cropRect(forPreviewImage image: CIImage) -> CGRect {
        var cropWidth: CGFloat = image.extent.size.width
        var cropHeight: CGFloat = image.extent.size.height
        if image.extent.size.width > image.extent.size.height {
            cropWidth = image.extent.size.width
            cropHeight = cropWidth * bounds.size.height / bounds.size.width
        }
        else if image.extent.size.width < image.extent.size.height {
            cropHeight = image.extent.size.height
            cropWidth = cropHeight * bounds.size.width / bounds.size.height
        }
        
        return image.extent.insetBy(dx: CGFloat((image.extent.size.width - cropWidth) / 2), dy: CGFloat((image.extent.size.height - cropHeight) / 2))
    }
    
    
    func rectangleDetectionConfidenceHighEnough(confidence:Float) -> Bool {
        return (confidence > 1.0)
    }
    
    func start() {
        isStopped = false
        captureSession?.startRunning()
        borderDetectTimeKeeper = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(VNCameraScanner.enableBorderDetectFrame), userInfo: nil, repeats: true)
        hideGLKView(false)
    }
    
    func stop() {
        isStopped = true
        captureSession?.stopRunning()
        borderDetectTimeKeeper?.invalidate()
        hideGLKView(true)
    }
    
    func enableBorderDetectFrame() {
        borderDetectFrame = true
    }
    
    func hideGLKView(_ hidden: Bool) {
        UIView.animate(withDuration: 0.1, animations: {() -> Void in
            self.glkView?.alpha = (hidden) ? 0.0 : 1.0
        }, completion: {(_ finished: Bool) -> Void in
            if !finished {
                return
            }
        })
    }
    
    func focus(at point: CGPoint, completionHandler: @escaping () -> Void) {
        let device: AVCaptureDevice? = captureDevice
        var pointOfInterest = CGPoint.zero
        let frameSize: CGSize = bounds.size
        pointOfInterest = CGPoint(x: CGFloat(point.y / frameSize.height), y: CGFloat(1.0 - (point.x / frameSize.width)))
        if (device?.isFocusPointOfInterestSupported)! && (device?.isFocusModeSupported(.autoFocus))! {
            do{
                try device?.lockForConfiguration()
                if (device?.isFocusModeSupported(.continuousAutoFocus))! {
                    device?.focusMode = .continuousAutoFocus
                    device?.focusPointOfInterest = pointOfInterest
                }
                if (device?.isExposurePointOfInterestSupported)! && (device?.isExposureModeSupported(.continuousAutoExposure))! {
                    device?.exposurePointOfInterest = pointOfInterest
                    device?.exposureMode = .continuousAutoExposure
                    completionHandler()
                }
                device?.unlockForConfiguration()
            }
            catch
            {
            
            }
        }
        else {
            completionHandler()
        }
    }
    
    
    func captureImage(withCompletionHander completionHandler: @escaping (_ imageFilePath: String) -> Void) {
        captureQueue.suspend()
        var videoConnection: AVCaptureConnection? = nil
        for connection: AVCaptureConnection in stillImageOutput?.connections as! [AVCaptureConnection] {
            for port: AVCaptureInputPort in connection.inputPorts as! [AVCaptureInputPort] {
                if port.mediaType.isEqual(AVMediaTypeVideo) {
                    videoConnection = connection
                    break
                }
            }
            if videoConnection != nil {
                break
            }
        }
        weak var weakSelf = self
        
        stillImageOutput?.captureStillImageAsynchronously(from: videoConnection, completionHandler: {(_ imageSampleBuffer: CMSampleBuffer?, _ error: Error?) -> Void in
            if error != nil {
                self.captureQueue.resume()
                return
            }
            let filePath: String =  NSTemporaryDirectory().stringByAppendingPathComponent(path: "vn_img_\(Int(Date().timeIntervalSince1970)).jpeg")//URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vn_img_\(Int(Date().timeIntervalSince1970)).jpeg").absoluteString
            
            autoreleasepool {
                var imageData: Data? = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageSampleBuffer)
                let image:UIImage = UIImage(data: imageData!)!
                var enhancedImage = CIImage(data: imageData!, options: [kCIImageColorSpace: NSNull()])
                imageData = nil
                if weakSelf?.cameraViewType == VNCameraViewType.blackAndWhite {
                    enhancedImage = self.filteredImageUsingEnhanceFilter(on: enhancedImage!)
                }
                else {
                    enhancedImage = self.filteredImageUsingContrastFilter(on: enhancedImage!)
                }
                if (weakSelf?.isEnableBorderDetection)! && self.rectangleDetectionConfidenceHighEnough(confidence: Float(self.imageDedectionConfidence)) {
                    let rectangleFeature = self.biggestRectangle(inRectangles: (self.highAccuracyRectangleDetector()?.features(in: enhancedImage!))!)
//                    let rectangleFeature: VNRectangleFeature? = VNRectangleFeature()
//                    rectangleFeature?.bottomLeft = (rectFet?.bottomLeft)!
//                    rectangleFeature?.bottomRight = (rectFet?.bottomRight)!
//                    rectangleFeature?.topLeft = (rectFet?.topLeft)!
//                    rectangleFeature?.topRight = (rectFet?.topRight)!
                    
                    if rectangleFeature != nil {
                        enhancedImage = self.correctPerspective(for: enhancedImage!, withFeatures: rectangleFeature!)
                    }
                }
                let transform = CIFilter(name: "CIAffineTransform")
                transform?.setValue(enhancedImage, forKey: kCIInputImageKey)
                let rotation = NSValue(cgAffineTransform: CGAffineTransform(rotationAngle: -90 * (.pi / 180)))
                transform?.setValue(rotation, forKey: "inputTransform")
                enhancedImage = transform?.outputImage
                if !(enhancedImage != nil) || (enhancedImage?.extent.isEmpty)! {
                    return
                }
                var ctx: CIContext? = nil
                if ctx == nil {
                    ctx = CIContext(options: [kCIContextWorkingColorSpace: NSNull()])
                }
                var bounds: CGSize = (enhancedImage?.extent.size)!
//                bounds = CGSize(width: CGFloat(floorf(bounds.width / 4) * 4), height: CGFloat(floorf(bounds.height / 4) * 4))
                bounds = CGSize(width: (bounds.width/4)*4, height: (bounds.height/4)*4)
                let extent = CGRect(x: CGFloat((enhancedImage?.extent.origin.x)!), y: CGFloat((enhancedImage?.extent.origin.y)!), width: CGFloat(bounds.width), height: CGFloat(bounds.height))
                let bytesPerPixel: Int = 8
                let rowBytes: uint = uint(Float(bytesPerPixel) * Float(bounds.width))
                let totalBytes: uint = uint(Float(rowBytes) * Float(bounds.height))
                let byteBuffer = malloc(Int(totalBytes))
                let colorSpace: CGColorSpace? = CGColorSpaceCreateDeviceRGB()
                ctx?.render(enhancedImage!, toBitmap: byteBuffer!, rowBytes: Int(rowBytes), bounds: extent, format: kCIFormatRGBA8, colorSpace: colorSpace)
                let bitmapContext = CGContext(data: byteBuffer, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: bytesPerPixel, bytesPerRow: Int(rowBytes), space: colorSpace!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)//kCGImageAlphaNoneSkipLast)
                let imgRef: CGImage? = bitmapContext?.makeImage()
                free(byteBuffer)
                if imgRef == nil {
                    return
                }
                self.saveCGImageAsJPEGToFilePath(imgRef: imgRef!, filePath: filePath)
                DispatchQueue.main.async(execute: {() -> Void in
                    completionHandler(filePath)
                    self.captureQueue.resume()
                })
                self.imageDedectionConfidence = 0.0
                
            }
            
        })

    }
    
    func saveCGImageAsJPEGToFilePath(imgRef:CGImage, filePath:String){
        
            let url: CFURL? = URL(fileURLWithPath: filePath) as CFURL
        if(url != nil)
        {
            guard let destination = CGImageDestinationCreateWithURL(url!, kUTTypePNG, 1, nil) else { print("error")
            return}
            CGImageDestinationAddImage(destination, imgRef, nil)
            CGImageDestinationFinalize(destination)
        }
    }
    
    func correctPerspective(for image: CIImage, withFeatures rectangleFeature: VNRectangleFeature) -> CIImage {
        var rectangleCoordinates = [String: Any]()
        rectangleCoordinates["inputTopLeft"] = CIVector(cgPoint: rectangleFeature.topLeft)
        rectangleCoordinates["inputTopRight"] = CIVector(cgPoint: rectangleFeature.topRight)
        rectangleCoordinates["inputBottomLeft"] = CIVector(cgPoint: rectangleFeature.bottomLeft)
        rectangleCoordinates["inputBottomRight"] = CIVector(cgPoint: rectangleFeature.bottomRight)
        return image.applyingFilter("CIPerspectiveCorrection", withInputParameters: rectangleCoordinates)
    }
}

public extension DispatchQueue {
    
    private static var _onceTracker = [String]()
    
    /**
     Executes a block of code, associated with a unique token, only once.  The code is thread safe and will
     only execute the code once even in the presence of multithreaded calls.
     
     - parameter token: A unique reverse DNS style name such as com.vectorform.<name> or a GUID
     - parameter block: Block to execute once
     */
    public class func once(token: String, block:(Void)->Void) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        
        if _onceTracker.contains(token) {
            return
        }
        
        _onceTracker.append(token)
        block()
    }
    
    
}

extension String {
    func stringByAppendingPathComponent(path: String) -> String {
        let nsSt = self as NSString
        return nsSt.appendingPathComponent(path)
    }
}

//extension CIRectangleFeature {
//    
//    convenience init(rectangleFeature feature: CIRectangleFeature) {
//        self.topLeft = feature.topLeft
//        self.topRight = feature.topRight
//        self.bottomRight = feature.bottomRight
//        self.bottomLeft = feature.bottomLeft
//    }
//}
