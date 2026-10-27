#!/usr/bin/env python3
"""Deterministically regenerate the checked-in Xcode project. No dependencies."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
def ident(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def q(text): return '"' + text.replace('\\','\\\\').replace('"','\\"') + '"'
objects = []
def obj(name, body): objects.append(f'{ident(name)} = {{ {body} }};'); return ident(name)
def listing(values): return '(' + ', '.join(values) + (',' if values else '') + ')'
app = sorted((root/'App').glob('*.swift')); tests = sorted((root/'AppTests').glob('*.swift'))
for path in app + tests:
    rel = str(path.relative_to(root)); obj(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
    obj('build:'+rel, f'isa = PBXBuildFile; fileRef = {ident(rel)};')
for filename, filetype in [('App/Info.plist','text.plist.xml'),('App/Stillwater.entitlements','text.plist.entitlements')]:
    obj(filename, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = {q(filename)}; sourceTree = SOURCE_ROOT;')
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Stillwater.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('testproduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = StillwaterTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
obj('appgroup', f'isa = PBXGroup; name = App; children = {listing([ident(str(p.relative_to(root))) for p in app]+[ident("App/Info.plist"),ident("App/Stillwater.entitlements")])}; sourceTree = "<group>";')
obj('testgroup', f'isa = PBXGroup; name = Tests; children = {listing([ident(str(p.relative_to(root))) for p in tests])}; sourceTree = "<group>";')
obj('products', f'isa = PBXGroup; name = Products; children = ({ident("product")}, {ident("testproduct")}); sourceTree = "<group>";')
obj('group', f'isa = PBXGroup; children = ({ident("appgroup")}, {ident("testgroup")}, {ident("products")}); sourceTree = "<group>";')
obj('package', 'isa = XCLocalSwiftPackageReference; relativePath = Core;')
# The product's optional package field accepts XCRemoteSwiftPackageReference only.
# Local packages resolve by product name through PBXProject.packageReferences.
for target, files in [('app',app),('test',tests)]:
    obj(target+'package', f'isa = XCSwiftPackageProductDependency; productName = VaultCore;')
    obj(target+'framework', f'isa = PBXBuildFile; productRef = {ident(target+"package")};')
    obj(target+'sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {listing([ident("build:"+str(p.relative_to(root))) for p in files])}; runOnlyForDeploymentPostprocessing = 0;')
    obj(target+'frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({ident(target+"framework")}); runOnlyForDeploymentPostprocessing = 0;')
    obj(target+'resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('proxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("app")}; remoteInfo = Stillwater;')
obj('dependency', f'isa = PBXTargetDependency; target = {ident("app")}; targetProxy = {ident("proxy")};')
for target, name, product, kind in [('app','Stillwater','product','application'),('test','StillwaterTests','testproduct','bundle.unit-test')]:
    obj(target, f'isa = PBXNativeTarget; buildConfigurationList = {ident(target+"configs")}; buildPhases = ({ident(target+"sources")}, {ident(target+"frameworks")}, {ident(target+"resources")}); buildRules = (); dependencies = {listing([ident("dependency")] if target == "test" else [])}; name = {name}; packageProductDependencies = ({ident(target+"package")}); productName = {name}; productReference = {ident(product)}; productType = "com.apple.product-type.{kind}";')
for scope in ['project','app','test']:
    for mode in ['Debug','Release']:
        values = {}
        if scope == 'project':
            values = dict(MACOSX_DEPLOYMENT_TARGET='14.0', SDKROOT='macosx', SWIFT_VERSION='5.0', ONLY_ACTIVE_ARCH='YES' if mode == 'Debug' else 'NO', CLANG_ENABLE_MODULES='YES', CLANG_ENABLE_OBJC_ARC='YES', GCC_C_LANGUAGE_STANDARD='gnu11', ENABLE_STRICT_OBJC_MSGSEND='YES', SWIFT_OPTIMIZATION_LEVEL='-Onone' if mode == 'Debug' else '-O', SWIFT_COMPILATION_MODE='singlefile' if mode == 'Debug' else 'wholemodule', ENABLE_TESTABILITY='YES' if mode == 'Debug' else 'NO', DEBUG_INFORMATION_FORMAT='dwarf' if mode == 'Debug' else 'dwarf-with-dsym', GCC_OPTIMIZATION_LEVEL='0' if mode == 'Debug' else 's')
        elif scope == 'app':
            values = dict(PRODUCT_NAME='Stillwater', PRODUCT_BUNDLE_IDENTIFIER='app.stillwater.passwords', INFOPLIST_FILE='App/Info.plist', CODE_SIGN_ENTITLEMENTS='App/Stillwater.entitlements', CODE_SIGN_STYLE='Automatic', ENABLE_APP_SANDBOX='YES', ENABLE_HARDENED_RUNTIME='YES', COMBINE_HIDPI_IMAGES='YES', LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks', SWIFT_EMIT_LOC_STRINGS='YES')
        else:
            values = dict(PRODUCT_NAME='StillwaterTests', PRODUCT_BUNDLE_IDENTIFIER='app.stillwater.passwords.tests', GENERATE_INFOPLIST_FILE='YES', CODE_SIGN_STYLE='Automatic', TEST_HOST='$(BUILT_PRODUCTS_DIR)/Stillwater.app/Contents/MacOS/Stillwater', BUNDLE_LOADER='$(TEST_HOST)', LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks')
        obj(scope+mode, 'isa = XCBuildConfiguration; buildSettings = {' + ''.join(f'{k} = {q(v)};' for k,v in values.items()) + f'}}; name = {mode};')
    obj(scope+'configs', f'isa = XCConfigurationList; buildConfigurations = ({ident(scope+"Debug")}, {ident(scope+"Release")}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; TargetAttributes = {{ {ident("app")} = {{ CreatedOnToolsVersion = 16.0; SystemCapabilities = {{ com.apple.Sandbox = {{ enabled = 1; }}; }}; }}; {ident("test")} = {{ CreatedOnToolsVersion = 16.0; TestTargetID = {ident("app")}; }}; }}; }}; buildConfigurationList = {ident("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {ident("group")}; productRefGroup = {ident("products")}; projectDirPath = ""; projectRoot = ""; packageReferences = ({ident("package")}); targets = ({ident("app")}, {ident("test")});')
project = root/'Stillwater.xcodeproj'; project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {ident("project")}; }}\n')
scheme = project/'xcshareddata/xcschemes'; scheme.mkdir(parents=True,exist_ok=True)
def ref(target,name,product): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(target)}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:Stillwater.xcodeproj"/>'
appref=ref('app','Stillwater','Stillwater.app'); testref=ref('test','StillwaterTests','StillwaterTests.xctest')
(scheme/'Stillwater.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{testref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="YES" debugDocumentVersioning="NO" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="NO"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
