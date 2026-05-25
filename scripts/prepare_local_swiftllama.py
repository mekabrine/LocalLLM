from pathlib import Path
import re
import shutil
import subprocess

VERSION = '1.41'
BUILD = '42'
APP_NAME = 'LocalLLM'
MIN_IOS = '16.1'
PACKAGE_DIR = Path('LocalPackages/SwiftLlama')
LLAMA_REVISION = 'b6d6c5289f1c9c677657c380591201ddb210b649'

if PACKAGE_DIR.exists():
    shutil.rmtree(PACKAGE_DIR)
PACKAGE_DIR.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['git', 'clone', '--depth', '1', '--branch', 'main', 'https://github.com/ShenghaiWang/SwiftLlama.git', str(PACKAGE_DIR)], check=True)

package_text = f'''// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftLlama",
    platforms: [
        .macOS(.v15),
        .iOS(.v16),
        .watchOS(.v11),
        .tvOS(.v18),
        .visionOS(.v2)
    ],
    products: [
        .library(name: "SwiftLlama", targets: ["SwiftLlama"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ggerganov/llama.cpp.git", revision: "{LLAMA_REVISION}")
    ],
    targets: [
        .target(
            name: "SwiftLlama",
            dependencies: [
                .product(name: "llama", package: "llama.cpp")
            ]
        ),
        .testTarget(name: "SwiftLlamaTests", dependencies: ["SwiftLlama"])
    ]
)
'''
if 'LlamaFramework' in package_text or 'binaryTarget' in package_text:
    raise SystemExit('Generated Package.swift still contains binary framework')
(PACKAGE_DIR / 'Package.swift').write_text(package_text)

model_path = PACKAGE_DIR / 'Sources/SwiftLlama/LlamaModel.swift'
text = model_path.read_text()
text = text.replace('        llama_backend_init()\n', '        _ = LlamaBackend.once\n')
text = text.replace('        llama_backend_free()\n', '')
if 'private enum LlamaBackend' not in text:
    text = text.replace('import Foundation\nimport llama\n\nclass LlamaModel {', 'import Foundation\nimport llama\n\nprivate enum LlamaBackend {\n    static let once: Void = { llama_backend_init() }()\n}\n\nclass LlamaModel {')
text = text.replace('tokens = tokenize(text: prompt.prompt, addBos: true)', 'tokens = try tokenize(text: prompt.prompt, addBos: true)')
text = text.replace('        tokens = try tokenize(text: prompt.prompt, addBos: true)\n\n        batch.clear()\n', '        tokens = try tokenize(text: prompt.prompt, addBos: true)\n        guard !tokens.isEmpty else { throw SwiftLlamaError.others("Prompt tokenization produced no tokens") }\n\n        batch.clear()\n')

safe_tokenize = '''    private func tokenize(text: String, addBos: Bool) throws -> [Token] {
        let byteCount = Int32(text.utf8.count)
        return try text.withCString { cText in
            let needed = llama_tokenize(model, cText, byteCount, nil, 0, addBos, false)
            var capacity = max(needed < 0 ? Int(-needed) : Int(needed), 8)
            var tokens = [Token](repeating: 0, count: capacity)
            var count = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_tokenize(model, cText, byteCount, buffer.baseAddress, Int32(buffer.count), addBos, false)
            }
            if count < 0 {
                capacity = max(Int(-count), capacity * 2, 8)
                tokens = [Token](repeating: 0, count: capacity)
                count = tokens.withUnsafeMutableBufferPointer { buffer in
                    llama_tokenize(model, cText, byteCount, buffer.baseAddress, Int32(buffer.count), addBos, false)
                }
            }
            guard count > 0 else { throw SwiftLlamaError.others("Prompt tokenization failed") }
            return Array(tokens.prefix(Int(count)))
        }
    }
'''
text, count = re.subn(r'\s*private func tokenize\(text:\s*String,\s*addBos:\s*Bool\)\s*(?:throws\s*)?->\s*\[Token\]\s*\{.*?\}\s*func clear\(\)', '\n' + safe_tokenize + '\n    func clear()', text, count=1, flags=re.S)
if count != 1:
    raise SystemExit('Failed to patch SwiftLlama tokenizer')
if 'llama_model_get_vocab' in text or 'private let vocab' in text or 'llama_tokenize(vocab,' in text:
    raise SystemExit('Unavailable vocab API remained in generated SwiftLlama patch')
model_path.write_text(text)

prompt_path = PACKAGE_DIR / 'Sources/SwiftLlama/Models/Prompt.swift'
prompt_text = prompt_path.read_text()
raw_alpaca = '    private func encodeAlpacaPrompt() -> String {\n        userMessage\n    }\n'
prompt_text, count = re.subn(r'\s*private func encodeAlpacaPrompt\(\) -> String \{.*?\}\s*private func encodeChatMLPrompt', '\n' + raw_alpaca + '\n    private func encodeChatMLPrompt', prompt_text, count=1, flags=re.S)
if count != 1:
    raise SystemExit('Failed to patch SwiftLlama Alpaca prompt wrapper')
prompt_path.write_text(prompt_text)

project = Path('project.yml')
project_text = project.read_text().replace('  SwiftLlama:\n    url: https://github.com/ShenghaiWang/SwiftLlama.git\n    from: 0.4.0', '  SwiftLlama:\n    path: LocalPackages/SwiftLlama')
project_text = re.sub(r'iOS: "[^"]+"', f'iOS: "{MIN_IOS}"', project_text)
project_text = re.sub(r'deploymentTarget: "[^"]+"', f'deploymentTarget: "{MIN_IOS}"', project_text)
if 'PRODUCT_NAME:' not in project_text:
    project_text = project_text.replace('        PRODUCT_BUNDLE_IDENTIFIER:', f'        PRODUCT_NAME: {APP_NAME}\n        PRODUCT_BUNDLE_IDENTIFIER:')
else:
    project_text = re.sub(r'PRODUCT_NAME: .*', f'PRODUCT_NAME: {APP_NAME}', project_text)
if 'IPHONEOS_DEPLOYMENT_TARGET:' not in project_text:
    project_text = project_text.replace('        SWIFT_VERSION:', f'        IPHONEOS_DEPLOYMENT_TARGET: "{MIN_IOS}"\n        SWIFT_VERSION:')
else:
    project_text = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET: "[^"]+"', f'IPHONEOS_DEPLOYMENT_TARGET: "{MIN_IOS}"', project_text)
project_text = re.sub(r'MARKETING_VERSION: "[^"]+"', f'MARKETING_VERSION: "{VERSION}"', project_text)
project_text = re.sub(r'CURRENT_PROJECT_VERSION: "[^"]+"', f'CURRENT_PROJECT_VERSION: "{BUILD}"', project_text)
project.write_text(project_text)

plist = Path('LocalGGUFChat/Resources/Info.plist')
plist_text = plist.read_text()
plist_text = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]+(</string>)', fr'\g<1>{APP_NAME}\2', plist_text)
plist_text = re.sub(r'(<key>CFBundleName</key>\s*<string>)[^<]+(</string>)', fr'\g<1>{APP_NAME}\2', plist_text)
plist_text = re.sub(r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)', fr'\g<1>{VERSION}\2', plist_text)
plist_text = re.sub(r'(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)', fr'\g<1>{BUILD}\2', plist_text)
plist.write_text(plist_text)

print(f'Prepared patched SwiftLlama from source only for {APP_NAME} iOS {MIN_IOS}+')