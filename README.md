# VNImageScanner
<img src="https://travis-ci.org/varun-naharia/VNImageScanner.svg?branch=master">
Code is based on <a href="https://github.com/mmackh/IPDFCameraViewController" >IPDFCameraViewController</a>. Improvements are needed so pull resqest are welcome.

![Screenshot](https://raw.githubusercontent.com/mmackh/IPDFCameraViewController/master/mockup.png)

# VNImageScanner

Welcome to the spiritual successor of [IPDFCameraViewController](https://github.com/mmackh/IPDFCameraViewController) and [MAImagePickerController](https://github.com/mmackh/MAImagePickerController-of-InstaPDF), that tries to unite a usable & simple camera component class into a single UIView. Initially written as an essential component of InstaPDF 4.0 for [instapdf.com](https://instapdf.com), it seemed too useful to keep closed source. Plus we're celebrating our 100,000 document upload 🎉🎉🎉

Leave all the hard work dealing with AVFoundation, border detection and OpenGL up to VNImageScanner. It includes:

  - Live border detection & perspective correction
  - Flash / Torch
  - Image filters
  - Simple API
 
**WARNING: MINIMUM iOS VERSION REQUIREMENT: 8.0**

Take a look at the sample project to find out how to use it.


## Installation

### Manual

To manually install the framework, drag and drop the `VNCameraScanner/VNCameraScanner.swift` files into your project.


## Author
Varun Naharia | Stackoverflow: [varun-naharia](http://stackoverflow.com/users/3851580/varun-naharia) | Web: [technaharia.in](http://technaharia.in)

## Todo's

 - Include more filters
 - Smoother animation between border detection frames
 - Improve confidence
