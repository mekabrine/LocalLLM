from pathlib import Path
import re
import shutil
import subprocess

VERSION = '1.18'
BUILD = '19'
PACKAGE_DIR = Path('LocalPackages/SwiftLlama')

if PACKAGE_DIR.exists():
    shutil.rmtree(PACKAGE_DIR)
PACKAGE_DIR.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['git', 'clone', '--depth', '1', '--branch', 'v0.4.0', 'https://github.com/ShenghaiWang/SwiftLlama.git', str(PACKAGE_DIR)], check=True)

model_path = PACKAGE_DIR / 'Sources/SwiftLlama/LlamaModel.swift'
text = model_path.read_text()
replacements = {
    '    private let model: Model\n': '    private let model: Model\n    private let vocab: OpaquePointer\n',
    '        self.model = model\n        guard let context = llama_new_context_with_model(model, configuration.contextParameters) else {': '        self.model = model\n        self.vocab = llama_model_get_vocab(model)\n        guard let context = llama_new_context_with_model(model, configuration.contextParameters) else {',
    '        llama_backend_init()\n': '        _ = LlamaBackend.once\n',
    '        llama_backend_free()\n': '',
    'llama_token_is_eog(model, newToken)': 'llama_token_is_eog(vocab, newToken)',
    'llama_token_to_piece(model, token, &piece, length, 0, false)': 'llama_token_to_piece(vocab, token, &piece, length, 0, false)',
    '        tokens = tokenize(text: prompt.prompt, addBos: true)\n        temporaryInvalidCChars = []\n': '        tokens = try tokenize(text: prompt.prompt, addBos: true)\n        guard !tokens.isEmpty else { throw SwiftLlamaError.others("Prompt tokenization produced no tokens") }\n        temporaryInvalidCChars = []\n'
}
for old, new in replacements.items():
    text = text.replace(old, new)

if 'private enum LlamaBackend' not in text:
    text = text.replace('import Foundation\nimport llama\n\nclass LlamaModel {', 'import Foundation\nimport llama\n\nprivate enum LlamaBackend { static let once: Void = { llama_backend_init() }() }\n\nclass LlamaModel {')

safe_tokenize = '''    private func tokenize(text: String, addBos: Bool) throws -> [Token] {
        let byteCount = Int32(text.utf8.count)
        let needed = text.withCString { llama_tokenize(vocab, $0, byteCount, nil, 0, addBos, false) }
        var capacity = max(needed < 0 ? Int(-needed) : Int(needed), 8)
        var tokens = [Token](repeating: 0, count: capacity)
        var count = text.withCString { cText in
            tokens.withUnsafeMutableBufferPointer { llama_tokenize(vocab, cText, byteCount, $0.baseAddress, Int32($0.count), addBos, false) }
        }
        if count < 0 {
            capacity = max(Int(-count), capacity * 2, 8)
            tokens = [Token](repeating: 0, count: capacity)
            count = text.withCString { cText in
                tokens.withUnsafeMutableBufferPointer { llama_tokenize(vocab, cText, byteCount, $0.baseAddress, Int32($0.count), addBos, false) }
            }
        }
        guard count > 0 else { throw SwiftLlamaError.others("Prompt tokenization failed") }
        return Array(tokens.prefix(Int(count)))
    }
'''
text, count = re.subn(r'    private func tokenize\(text: String, addBos: Bool\) -> \[Token\] \{.*?    \}\n\n    func clear\(\)', safe_tokenize + '\n    func clear()', text, count=1, flags=re.S)
if count != 1:
    raise SystemExit('Failed to patch SwiftLlama tokenizer')
model_path.write_text(text)

prompt_path = PACKAGE_DIR / 'Sources/SwiftLlama/Models/Prompt.swift'
prompt_text = prompt_path.read_text()
raw_alpaca = '    private func encodeAlpacaPrompt() -> String {\n        userMessage\n    }\n'
prompt_text, count = re.subn(r'    private func encodeAlpacaPrompt\(\) -> String \{.*?    \}\n\n    private func encodeChatMLPrompt', raw_alpaca + '\n    private func encodeChatMLPrompt', prompt_text, count=1, flags=re.S)
if count != 1:
    raise SystemExit('Failed to patch SwiftLlama Alpaca prompt wrapper')
prompt_path.write_text(prompt_text)

project = Path('project.yml')
project_text = project.read_text().replace('  SwiftLlama:\n    url: https://github.com/ShenghaiWang/SwiftLlama.git\n    from: 0.4.0', '  SwiftLlama:\n    path: LocalPackages/SwiftLlama')
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
