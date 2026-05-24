from pathlib import Path
import re
import shutil
import subprocess

VERSION = '1.25'
BUILD = '26'
PACKAGE_DIR = Path('LocalPackages/SwiftLlama')

if PACKAGE_DIR.exists():
    shutil.rmtree(PACKAGE_DIR)
PACKAGE_DIR.parent.mkdir(parents=True, exist_ok=True)
subprocess.run([
    'git', 'clone', '--depth', '1', '--branch', 'main',
    'https://github.com/ShenghaiWang/SwiftLlama.git',
    str(PACKAGE_DIR)
], check=True)

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

safe_tokenize = '''    private func tokenize(text: String, addBos: Bool) throws -> [Token] {
        let byteCount = Int32(text.utf8.count)
        let needed = llama_tokenize(model, text, byteCount, nil, 0, addBos, false)
        var capacity = max(needed < 0 ? Int(-needed) : Int(needed), 8)
        var tokens = [Token](repeating: 0, count: capacity)
        var count = tokens.withUnsafeMutableBufferPointer { buffer in
            llama_tokenize(model, text, byteCount, buffer.baseAddress, Int32(buffer.count), addBos, false)
        }
        if count < 0 {
            capacity = max(Int(-count), capacity * 2, 8)
            tokens = [Token](repeating: 0, count: capacity)
            count = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_tokenize(model, text, byteCount, buffer.baseAddress, Int32(buffer.count), addBos, false)
            }
        }
        guard count > 0 else { throw SwiftLlamaError.others("Prompt tokenization failed") }
        return Array(tokens.prefix(Int(count)))
    }
'''
text, count = re.subn(
    r'    private func tokenize\(text: String, addBos: Bool\) -> \[Token\] \{.*?    \}\n\n    func clear\(\)',
    safe_tokenize + '\n    func clear()',
    text,
    count=1,
    flags=re.S
)
if count != 1:
    raise SystemExit('Failed to patch SwiftLlama tokenizer')
if 'llama_model_get_vocab' in text or 'private let vocab' in text:
    raise SystemExit('Generated SwiftLlama patch uses unavailable vocab API')
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
project_text = re.sub(r'MARKETING_VERSION: "[^"]+"', f'MARKETING_VERSION: "{VERSION}"', project_text)
project_text = re.sub(r'CURRENT_PROJECT_VERSION: "[^"]+"', f'CURRENT_PROJECT_VERSION: "{BUILD}"', project_text)
project.write_text(project_text)

plist = Path('LocalGGUFChat/Resources/Info.plist')
if plist.exists():
    plist_text = plist.read_text()
    plist_text = re.sub(r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]+(</string>)', r'\g<1>LocalLLM\2', plist_text)
    plist_text = re.sub(r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)', fr'\g<1>{VERSION}\2', plist_text)
    plist_text = re.sub(r'(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)', fr'\g<1>{BUILD}\2', plist_text)
    plist.write_text(plist_text)

print('Prepared patched local SwiftLlama package')
