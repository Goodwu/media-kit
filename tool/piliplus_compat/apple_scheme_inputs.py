"""Exact additional scheme/workspace changes observed in the T1 Apple builds."""
import re
from generated_apple import blob, checked_bytes
from generated_macos import migrate_macos_config

GENERATORS = {
 'packages/flutter_tools/lib/src/ios/migrations/metal_api_validation_migration.dart': '590b7459532b250c101c09560fae8726a4e630f9',
 'packages/flutter_tools/lib/src/migrations/lldb_init_migration.dart': '3751808b96ac7e432360a79685b77770e534dfa5',
}


def verify_scheme_generators(flutter):
    for path, expected in GENERATORS.items():
        if blob(checked_bytes(flutter / path, flutter)) != expected:
            raise ValueError('Apple scheme generator changed: ' + path)


def metal(text):
    if 'enableGPUValidationMode' in text:
        return text
    pattern = r'(\s)*debugServiceExtension = "internal"\n'
    def replace(match):
        group = match.group(0)
        count = group.split('debugServiceExtension')[0].count(' ')
        return group + ' ' * count + 'enableGPUValidationMode = "1"\n'
    return re.sub(pattern, replace, text, count=1)


def expected_scheme(platform, data):
    if platform == 'macos':
        data = migrate_macos_config('macos/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme', data)
    text = metal(data.decode('utf-8'))
    if platform == 'ios' and 'customLLDBInitFile' not in text:
        key = 'selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"'
        text = text.replace(key, key + '\n      customLLDBInitFile = "$(SRCROOT)/Flutter/ephemeral/flutter_lldbinit"')
    return text.encode('utf-8')


def expected_workspace(data):
    text = data.decode('utf-8')
    # CocoaPods UserProjectIntegrator#create_workspace adds the Pods project
    # reference; preserve every byte of all other workspace references/settings.
    if 'location = "group:Pods/Pods.xcodeproj"' in text:
        return data
    if text.count('</Workspace>') != 1:
        raise ValueError('Unknown workspace representation')
    return text.replace('</Workspace>', '   <FileRef\n      location = "group:Pods/Pods.xcodeproj">\n   </FileRef>\n</Workspace>').encode('utf-8')


def capture_scheme_inputs(flutter, originals, platform):
    verify_scheme_generators(flutter)
    records = {}
    for path, original in originals.items():
        if path == f'{platform}/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme':
            after = expected_scheme(platform, original)
            generator = 'Flutter MetalAPIValidationMigrator / LLDBInitMigration / Xcode metadata'
        elif path == f'{platform}/Runner.xcworkspace/contents.xcworkspacedata':
            after = expected_workspace(original)
            generator = 'CocoaPods UserProjectIntegrator exact Pods project reference'
        else:
            continue
        records[path] = {'before': blob(original), 'after': blob(after), 'generator': generator}
    return records
