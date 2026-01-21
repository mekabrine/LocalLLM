# LocalGGUFChat (iOS 15+)

Offline-first chat app that runs local GGUF models on-device using a `llama.cpp`-compatible Swift package.

## Build (Xcode)
1. Install XcodeGen: `brew install xcodegen`
2. From repo root: `xcodegen generate`
3. Open `LocalGGUFChat.xcodeproj` and run on device/simulator.

## Model files
Use the in-app model picker to select a `.gguf` file from the Files app. The app stores a security-scoped bookmark so the file can be reopened across launches.

## Notes
- The runtime integration uses `srgtuszy/llama-cpp-swift` (AsyncStream token streaming). citeturn1view1
- Prompt formatting is simple and model-agnostic; you may want to adjust to the specific instruct/chat template for your model.

