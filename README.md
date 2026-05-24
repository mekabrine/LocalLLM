# LocalLLM / LocalGGUFChat

Offline-first iOS chat app for running local `.gguf` models on device through the SwiftLlama llama.cpp wrapper.

## Features

- Multiple saved chats with Core Data persistence
- Multiple imported `.gguf` model references
- Security-scoped model bookmarks so models can stay in the Files app instead of being copied into the app container
- Streaming assistant replies
- Typing indicator while the first streamed tokens are loading
- Editable messages with downstream messages marked out of date
- Per-chat model selection
- Settings page for:
  - temperature
  - top-p
  - max output length
  - stop sequences
  - default model for new chats
  - importing one or more `.gguf` files
- Bundle identifier: `com.mekabrine.localllm`

## Requirements

- Xcode 16.4 or newer
- iOS 18.0 or newer
- XcodeGen
- A compatible `.gguf` model small enough for the target device memory

## Build locally with Xcode

```bash
brew install xcodegen
xcodegen generate
open LocalGGUFChat.xcodeproj
```

Then select the `LocalGGUFChat` scheme and run on a device or simulator.

## Model files

Use either:

1. **Settings → Import .gguf Models**, which supports multiple files.
2. **New Chat → Import .gguf Files**.
3. **Chat → CPU icon → Import .gguf Files**.

The app stores security-scoped bookmarks for imported files. Large model files remain where the user picked them from in Files.

## GitHub Actions unsigned IPA

This repo includes `.github/workflows/build-unsigned-ipa.yml`.

The workflow runs on pushes to `main` and can also be started manually with **Actions → Build Unsigned IPA → Run workflow**.

The workflow:

1. Checks out the repo.
2. Installs XcodeGen.
3. Generates `LocalGGUFChat.xcodeproj`.
4. Resolves Swift packages.
5. Builds the iPhoneOS Release app with code signing disabled.
6. Packages `Payload/LocalGGUFChat.app` into `LocalLLM-unsigned.ipa`.
7. Uploads it as the `LocalLLM-unsigned-ipa` artifact.

Download the artifact from the completed workflow run. Tools such as SideStore or Sideloadly normally re-sign the app during install; iOS still requires a signed app on device, even when the IPA artifact itself is produced unsigned.

## Notes

- The runtime integration uses [`ShenghaiWang/SwiftLlama`](https://github.com/ShenghaiWang/SwiftLlama), which wraps llama.cpp and exposes prompt streaming through `start(for:)`.
- Temperature, top-p, max output, and stop sequences are stored in app settings. Stop sequences and max output are enforced around the stream. Sampling support depends on what the SwiftLlama wrapper exposes internally.
- Prompt formatting is intentionally simple and model-agnostic. Some models may perform better with a model-specific chat template.
