#!/usr/bin/env python3
"""Generate a dependency-free Xcode project. Run after adding/removing app files."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def obj(object_key, isa, **fields):
    key = ident(object_key)
    objects[key] = {'isa': isa, **fields}
    return key

def reference(path, kind):
    return obj('file:' + path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='SOURCE_ROOT')

def build(reference_id):
    return obj('build:' + reference_id, 'PBXBuildFile', fileRef=reference_id)

def render(value, indent=0):
    pad = '\t' * indent
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (indent+1) + json.dumps(k) + ' = ' + render(v, indent+1) + ';\n' for k,v in value.items()) + pad + '}'
    if isinstance(value, list):
        return '(\n' + ''.join('\t' * (indent+1) + render(v, indent+1) + ',\n' for v in value) + pad + ')'
    return json.dumps(str(value))

source_paths = sorted((ROOT/'App').rglob('*.swift')) + sorted((ROOT/'Sources').rglob('*.swift'))
app_files = [reference(str(path.relative_to(ROOT)), 'sourcecode.swift') for path in source_paths]
assets = reference('App/Resources/Assets.xcassets', 'folder.assetcatalog')
privacy = reference('App/Resources/PrivacyInfo.xcprivacy', 'text.xml')
info = reference('App/Resources/Info.plist', 'text.plist.xml')
entitlements = [reference('App/Resources/' + p, 'text.plist.entitlements') for p in ['Local.entitlements', 'Cloud.entitlements']]
configs = {name: reference('Config/' + name + '.xcconfig', 'text.xcconfig') for name in ['Debug', 'Release', 'CloudDebug', 'CloudRelease']}
common = reference('Config/Common.xcconfig', 'text.xcconfig')
application = obj('application-group', 'PBXGroup', name='Application', children=app_files + [assets, privacy, info] + entitlements, sourceTree='<group>')
configuration = obj('configuration-group', 'PBXGroup', name='Configuration', children=list(configs.values())+[common], sourceTree='<group>')
product = obj('product', 'PBXFileReference', explicitFileType='wrapper.application', path='PocketLedger.app', sourceTree='BUILT_PRODUCTS_DIR', includeInIndex=0)
products = obj('products', 'PBXGroup', name='Products', children=[product], sourceTree='<group>')
main = obj('main', 'PBXGroup', children=[application, configuration, reference('README.md', 'net.daringfireball.markdown'), products], sourceTree='<group>')

frameworks = obj('frameworks', 'PBXFrameworksBuildPhase', buildActionMask=2147483647,
                 files=[], runOnlyForDeploymentPostprocessing=0)
sources = obj('sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=[build(f) for f in app_files], runOnlyForDeploymentPostprocessing=0)
resources = obj('resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=[build(assets), build(privacy)], runOnlyForDeploymentPostprocessing=0)

project_configs = []
target_configs = []
for name, config in configs.items():
    project_configs.append(obj('project-config:'+name, 'XCBuildConfiguration', name=name, buildSettings={'SDKROOT':'iphoneos', 'CLANG_ENABLE_MODULES':'YES'}))
    target_configs.append(obj('target-config:'+name, 'XCBuildConfiguration', name=name, baseConfigurationReference=config, buildSettings={}))
project_config_list = obj('project-configs', 'XCConfigurationList', buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')
target_config_list = obj('target-configs', 'XCConfigurationList', buildConfigurations=target_configs, defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')
target = obj('target', 'PBXNativeTarget', name='PocketLedger', productName='PocketLedger', productType='com.apple.product-type.application',
             productReference=product, buildConfigurationList=target_config_list, buildPhases=[sources,frameworks,resources], buildRules=[], dependencies=[])
project = obj('project', 'PBXProject', attributes={'BuildIndependentTargetsInParallel':'YES', 'LastUpgradeCheck':'2700', 'TargetAttributes':{target:{'CreatedOnToolsVersion':'27.0', 'ProvisioningStyle':'Automatic'}}},
              buildConfigurationList=project_config_list, compatibilityVersion='Xcode 14.0', developmentRegion='en', hasScannedForEncodings=0,
              knownRegions=['en','Base'], mainGroup=main, productRefGroup=products, projectDirPath='', projectRoot='', targets=[target])
document = {'archiveVersion':1, 'classes':{}, 'objectVersion':56, 'objects':objects, 'rootObject':project}
(ROOT/'PocketLedger.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n'+render(document)+'\n')

for name, debug, release in [('PocketLedger', 'Debug', 'Release'), ('PocketLedger iCloud', 'CloudDebug', 'CloudRelease')]:
    scheme = ET.Element('Scheme', LastUpgradeVersion='2700', version='1.7')
    action = ET.SubElement(scheme, 'BuildAction', parallelizeBuildables='YES', buildImplicitDependencies='YES')
    entries = ET.SubElement(action, 'BuildActionEntries')
    entry = ET.SubElement(entries, 'BuildActionEntry', buildForTesting='YES', buildForRunning='YES', buildForProfiling='YES', buildForArchiving='YES', buildForAnalyzing='YES')
    def buildable(parent):
        ET.SubElement(parent,'BuildableReference',BuildableIdentifier='primary',BlueprintIdentifier=target,BuildableName='PocketLedger.app',BlueprintName='PocketLedger',ReferencedContainer='container:PocketLedger.xcodeproj')
    buildable(entry)
    ET.SubElement(scheme, 'TestAction', buildConfiguration=debug, selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB', selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB', shouldUseLaunchSchemeArgsEnv='YES')
    launch = ET.SubElement(scheme, 'LaunchAction', buildConfiguration=debug, selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB', selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB', launchStyle='0', useCustomWorkingDirectory='NO', ignoresPersistentStateOnLaunch='NO', debugDocumentVersioning='YES', allowLocationSimulation='YES')
    buildable(ET.SubElement(launch, 'BuildableProductRunnable', runnableDebuggingMode='0'))
    profile = ET.SubElement(scheme, 'ProfileAction', buildConfiguration=release, shouldUseLaunchSchemeArgsEnv='YES', useCustomWorkingDirectory='NO', debugDocumentVersioning='YES')
    buildable(ET.SubElement(profile, 'BuildableProductRunnable', runnableDebuggingMode='0'))
    ET.SubElement(scheme, 'AnalyzeAction', buildConfiguration=debug)
    ET.SubElement(scheme, 'ArchiveAction', buildConfiguration=release, revealArchiveInOrganizer='YES')
    ET.indent(scheme)
    ET.ElementTree(scheme).write(ROOT/'PocketLedger.xcodeproj/xcshareddata/xcschemes'/f'{name}.xcscheme',encoding='utf-8',xml_declaration=True)
print(f'Generated project with {len(app_files)} Swift source files and 2 shared schemes.')
