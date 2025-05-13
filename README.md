# SwiftUI Active Speaker Detection Example 

**Note:** This project builds upon my [Speech Diarization Starter Project](https://github.com/carlosmbe/SpeechDiarizationStarter). Setup follows a similar process. 

## Project Overview

A Swift implementation of **Active Speaker Detection** combining:
- Speech Diarization and Transcription models  
- Vision models

### Related Articles  
- [Active Speaker Detection Using Swift](https://carlosmbe.hashnode.dev/active-speaker-detection-using-swift-for-ios-and-other-apple-platforms) - Full tutorial  
- [Sherpa-Onnx for Apple Development](https://carlosmbe.hashnode.dev/running-speech-models-with-swift-using-sherpa-onnx-for-apple-development) - Speech Diarization deep dive  

## Getting Started

### 1. Required Frameworks

Before building this project, ensure the required frameworks are in place:

- **`onnxruntime`** is too large to be included directly. You must [download it manually](#download-required-framework).
- **`Sherpa-Onnx.xcframework`** must also be built and added to your project. See [Building from Sherpa Onnx](#building-from-sherpa-onnx).

Without these, building the project will fail.

> **Note:** After setup, test the app using the File Picker to load an audio file. Alternatively, hardcode a file path in `ContentView` (line 18) for testing.

---

### Download Required Framework

Download the `onnxruntime` framework:

[onnxruntime.xcframework-1.17.1.tar.bz2](https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.17.1/onnxruntime.xcframework-1.17.1.tar.bz2)

**Steps:**
1. Extract the archive.
2. Copy `onnxruntime.xcframework` into your Xcode project directory.

---

### Building from Sherpa Onnx

To build `Sherpa-Onnx.xcframework`, follow these steps:

Visit this link for more detailed [build instructions](https://k2-fsa.github.io/sherpa/onnx/ios/build-sherpa-onnx-swift.html).

#### Summary of Build Steps
1. Clone the reposity 
   ```bash
    git clone https://github.com/k2-fsa/sherpa-onnx 
2. Enter the repo directory
    ```bash
    cd sherpa-onnx
   
3. Run the ios build script with
    ```bash
    ./build-ios.sh
   
4. After the script completes, a `build-ios` folder will be created.

5. Copy `sherpa-onnx.xcframework` from build-ios into your Xcode project.

6. You’ll also find `onnxruntime.xcframework` in:
    ```bash
    ios-onnxruntime/1.17.1/onnxruntime.xcframework
> This is the same xcframework from the previous section 
   
<img width="334" alt="Screenshot offiles to copy" src="https://github.com/user-attachments/assets/aa1504b1-019f-4d49-8756-86d7915c3421" />

## The Actual App

The app expects a video file named **`Clip.mp4`** in your app bundle.  
If you'd prefer to load videos another way, you can modify the initialization of `CombinedAnalysisView` located in the `ASDFiles` folder.

> While most video formats work, this app uses **AVFoundation**, via AudioKit, to process video files. Some video codecs may not be supported by Apple.  
> If you encounter errors during file conversion, try a different video file with a more common codec.

---

### Absolute Cinema (Demo Video)

Here's a demo of the app in action (make sure to unmute):

https://github.com/user-attachments/assets/446daafe-3cf1-47ff-aeb2-d70b49f14f4e

> **Disclaimer:** This video being used for the demo is copyrighted by *Trash Taste* and is used here under *fair use* for demo and educational purposes only.


## Contributing

Contributions and suggestions are welcome as the project is actively evolving.

---

Updates and additional documentation will be provided as development progresses.
