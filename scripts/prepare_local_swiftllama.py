from pathlib import Path
import re
import shutil
import subprocess

PACKAGE_DIR = Path('LocalPackages/SwiftLlama')

if PACKAGE_DIR.exists():
    shutil.rmtree(PACKAGE_DIR)
PACKAGE_DIR.parent.mkdir(parents=True, exist_ok=True)

subprocess.run([
    'git', 'clone', '--depth', '1', '--branch', 'v0.4.0',
    'https://github.com/ShenghaiWang/SwiftLlama.git',
    str(PACKAGE_DIR)
], check=True)

model_path = PACKAGE_DIR / 'Sources/SwiftLlama/LlamaModel.swift'
text = model_path.read_text()

text = text.replace('    private let model: Model\n', '    private let model: Model\n    private let vocab: OpaquePointer\n')
text = text.replace(
    '        self.model = model\n'
    '        guard let context = llama_new_context_with_model(model, configuration.contextParameters) else {',
    '        self.model = model\n'
    '        self.vocab = llama_model_get_vocab(model)\n'
    '        guard let context = llama_new_context_with_model(model, configuration.contextParameters) else {'
)

text = text.replace('        llama_backend_init()\n', '        _ = LlamaBackend.once\n')
text = text.replace('        llama_backend_free()\n', '')
text = text.replace('llama_token_is_eog(model, newToken)', 'llama_token_is_eog(vocab, newToken)')
text = text.replace('llama_token_to_piece(model, token, &piece, length, 0, false)', 'llama_token_to_piece(vocab, token, &piece, length, 0, false)')

if 'private enum LlamaBackend' not in text:
    text = text.replace(
        'import Foundation\nimport llama\n\nclass LlamaModel {',
        'import Foundation\nimport llama\n\nprivate enum LlamaBackend {\n'
        '    static let once: Void = {\n'
        '        llama_backend_init()\n'
        '    }()\n'
        '}\n\nclass LlamaModel {'
    )

text = text.replace(
    '        tokens = tokenize(text: prompt.prompt, addBos: true)\n'
    '        temporaryInvalidCChars = []\n',
    '        tokens = try tokenize(text: prompt.prompt, addBos: true)\n'
    '        guard !tokens.isEmpty else {\n'
    '            throw SwiftLlamaError.others("Prompt tokenization produced no tokens")\n'
    '        }\n'
    '        temporaryInvalidCChars = []\n'
)

safe_tokenize = '''    private func tokenize(text: String, addBos: Bool) throws -> [Token] {
        let byteCount = Int32(text.utf8.count)
        let required = text.withCString { cText -> Int32 in
            llama_tokenize(vocab, cText, byteCount, nil, 0, addBos, false)
        }

        var capacity: Int
        if required < 0 {
            capacity = Int(-required)
        } else if required > 0 {
            capacity = Int(required)
        } else {
            throw SwiftLlamaError.others("Prompt tokenization failed")
        }
        capacity = max(capacity, 8)

        var tokens = [Token](repeating: 0, count: capacity)
        let count = text.withCString { cText -> Int32 in
            tokens.withUnsafeMutableBufferPointer { buffer in
                llama_tokenize(vocab, cText, byteCount, buffer.baseAddress, Int32(buffer.count), addBos, false)
            }
        }

        if count < 0 {
            let retryCapacity = max(Int(-count), capacity * 2, 8)
            tokens = [Token](repeating: 0, count: retryCapacity)
            let retryCount = text.withCString { cText -> Int32 in
                tokens.withUnsafeMutableBufferPointer { buffer in
                    llama_tokenize(vocab, cText, byteCount, buffer.baseAddress, Int32(buffer.count), addBos, false)
                }
            }
            guard retryCount > 0 else {
                throw SwiftLlamaError.others("Prompt tokenization failed")
            }
            return Array(tokens.prefix(Int(retryCount)))
        }

        guard count > 0 else {
            throw SwiftLlamaError.others("Prompt tokenization failed")
        }
        return Array(tokens.prefix(Int(count)))
    }
'''

pattern = r'    private func tokenize\(text: String, addBos: Bool\) -> \[Token\] \{.*?    \}\n\n    func clear\(\)'
patched, count = re.subn(pattern, safe_tokenize + '\n    func clear()', text, count=1, flags=re.S)
if count != 1:
    raise SystemExit('Failed to patch SwiftLlama tokenizer')
model_path.write_text(patched)

project = Path('project.yml')
project_text = project.read_text()
project_text = project_text.replace(
    '  SwiftLlama:\n    url: https://github.com/ShenghaiWang/SwiftLlama.git\n    from: 0.4.0',
    '  SwiftLlama:\n    path: LocalPackages/SwiftLlama'
)
for old_version in ['1.5', '1.6', '1.7', '1.8', '1.9']:
    project_text = project_text.replace(f'MARKETING_VERSION: "{old_version}"', 'MARKETING_VERSION: "1.10"')
for old_build in ['6', '7', '8', '9', '10']:
    project_text = project_text.replace(f'CURRENT_PROJECT_VERSION: "{old_build}"', 'CURRENT_PROJECT_VERSION: "11"')
project.write_text(project_text)

plist = Path('LocalGGUFChat/Resources/Info.plist')
if plist.exists():
    plist_text = plist.read_text()
    plist_text = re.sub(
        r'(<key>CFBundleDisplayName</key>\s*<string>)[^<]+(</string>)',
        r'\g<1>LocalLLM\2',
        plist_text
    )
    plist_text = re.sub(
        r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+(</string>)',
        r'\g<1>1.10\2',
        plist_text
    )
    plist_text = re.sub(
        r'(<key>CFBundleVersion</key>\s*<string>)[^<]+(</string>)',
        r'\g<1>11\2',
        plist_text
    )
    plist.write_text(plist_text)

print('Prepared patched local SwiftLlama package')
