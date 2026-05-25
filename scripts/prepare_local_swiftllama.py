from pathlib import Path
import re
import shutil
import subprocess

VERSION = '1.36'
BUILD = '37'
APP_NAME = 'LocalLLM'
MIN_IOS = '16.1'
PACKAGE_DIR = Path('LocalPackages/SwiftLlama')

if PACKAGE_DIR.exists():
    shutil.rmtree(PACKAGE_DIR)
PACKAGE_DIR.parent.mkdir(parents=True, exist_ok=True)
subprocess.run([
    'git', 'clone', '--depth', '1', '--branch', 'main',
    'https://github.com/ShenghaiWang/SwiftLlama.git',
    str(PACKAGE_DIR)
], check=True)

package_path = PACKAGE_DIR / 'Package.swift'
package_text = package_path.read_text()
if 'platforms:' in package_text:
    package_text = re.sub(r'\.iOS\(\.v\d+(?:_\d+)?\)', '.iOS(.v16)', package_text)
else:
    package_text = package_text.replace(
        'let package = Package(\n    name: "SwiftLlama",',
        'let package = Package(\n    name: "SwiftLlama",\n    platforms: [.iOS(.v16)],'
    )
package_path.write_text(package_text)

model_path = PACKAGE_DIR / 'Sources/SwiftLlama/LlamaModel.swift'
text = model_path.read_text()

text = text.replace('        llama_backend_init()\n', '        _ = LlamaBackend.once\n')
text = text.replace('        llama_backend_free()\n', '')
text = text.replace('tokens = tokenize(text: prompt.prompt, addBos: true)', 'tokens = try tokenize(text: prompt.prompt, addBos: true)')
text = text.replace(
    '        tokens = try tokenize(text: prompt.prompt, addBos: true)\n\n        batch.clear()\n',
    '        tokens = try tokenize(text: prompt.prompt, addBos: true)\n        guard !tokens.isEmpty else { throw SwiftLlamaError.others("Prompt tokenization produced no tokens") }\n\n        batch.clear()\n'
)

if 'private enum LlamaBackend' not in text:
    text = text.replace(
        'import Foundation\nimport llama\n\nclass LlamaModel {',
        'import Foundation\nimport llama\n\nprivate enum LlamaBackend {\n    static let once: Void = { llama_backend_init() }()\n}\n\nclass LlamaModel {'
    )

if 'private let vocab: OpaquePointer' not in text:
    text, count = re.subn(
        r'(    private let model: OpaquePointer\n)',
        r'\1    private let vocab: OpaquePointer\n',
        text,
        count=1
    )
    if count != 1:
        raise SystemExit('Failed to add SwiftLlama vocab property')

if 'self.vocab = llama_model_get_vocab(model)' not in text:
    text, count = re.subn(
        r'(        self\.model = model\n)',
        r'\1        self.vocab = llama_model_get_vocab(model)\n',
        text,
        count=1
    )
    if count != 1:
        raise SystemExit('Failed to initialize SwiftLlama vocab pointer')

text = text.replace('llama_token_is_eog(model,', 'llama_token_is_eog(vocab,')
text = text.replace('llama_token_to_piece(model,', 'llama_token_to_piece(vocab,')
text = text.replace('llama_tokenize(model,', 'llama_tokenize(vocab,')

safe_tokenize = '''    private func tokenize(text: String, addBos: Bool) throws -> [Token] {
        let byteCount = Int32(text.utf8.count)
        return try text.withCString { cText in
            let needed = llama_tokenize(vocab, cText, byteCount, nil, 0, addBos, false)
            var capacity = max(needed < 0 ? Int(-needed) : Int(needed), 8)
            var tokens = [Token](repeating: 0, count: capacity)
            var count = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_tokenize(vocab, cText, byteCount, buffer.baseAddress, Int32(buffer.count), addBos, false)
            }
            if count < 0 {
                capacity = max(Int(-count), capacity * 2, 8)
                tokens = [Token](repeating: 0, count: capacity)
                count = tokens.withUnsafeMutableBufferPointer { buffer in
                    llama_tokenize(vocab, cText, byteCount, buffer.baseAddress, Int32(buffer.count), addBos, false)
                }
            }
            guard count > 0 else { throw SwiftLlamaError.others("Prompt tokenization failed") }
            return Array(tokens.prefix(Int(count)))
        }
    }
'''
text, count = re.subn(
    r'    private func tokenize\(text: String, addBos: Bool\) (?:throws )?-> \[Token\] \{.*?    \}\n\n    func clear\(\)',
    safe_tokenize + '\n    func clear()',
    text,
    count=1,
    flags=re.S
)
if count != 1:
    raise SystemExit('Failed to patch SwiftLlama tokenizer')
if 'private let vocab: OpaquePointer' not in text or 'llama_model_get_vocab(model)' not in text or 'llama_tokenize(vocab,' not in text:
    raise SystemExit('Generated SwiftLlama patch did not apply vocab-backed tokenizer')
model_path.write_text(text)

prompt_path = PACKAGE_DIR / 'Sources/SwiftLlama/Models/Prompt.swift'
prompt_text = prompt_path.read_text()
raw_alpaca = '    private func encodeAlpacaPrompt() -> String {\n        userMessage\n    }\n'
prompt_text, count = re.subn(
    r'    private func encodeAlpacaPrompt\(\) -> String \{.*?    \}\n\n    private func encodeChatMLPrompt',
    raw_alpaca + '\n    private func encodeChatMLPrompt',
    prompt_text,
    count=1,
    flags=re.S
)
if count != 1:
    raise SystemExit('Failed to patch SwiftLlama Alpaca prompt wrapper')
prompt_path.write_text(prompt_text)

project = Path('project.yml')
project_text = project.read_text()
project_text = project_text.replace(
    '  SwiftLlama:\n    url: https://github.com/ShenghaiWang/SwiftLlama.git\n    from: 0.4.0',
    '  SwiftLlama:\n    path: LocalPackages/SwiftLlama'
)
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
if plist.exists():
    plist_text = plist.read_text()
    plist_text = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]+(</string>)', fr'\g<1>{APP_NAME}\2', plist_text)
    plist_text = re.sub(r'(<key>CFBundleName</key>\s*<string>)[^<]+(</string>)', fr'\g<1>{APP_NAME}\2', plist_text)
    plist_text = re.sub(r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)', fr'\g<1>{VERSION}\2', plist_text)
    plist_text = re.sub(r'(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)', fr'\g<1>{BUILD}\2', plist_text)
    plist.write_text(plist_text)

print(f'Prepared patched SwiftLlama package and {APP_NAME} metadata for iOS {MIN_IOS}+')
