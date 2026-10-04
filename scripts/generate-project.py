#!/usr/bin/env python3
"""Regenerate the checked-in native Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parent.parent
objects = {}

def ident(name):
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()

def obj(object_key, isa, **values):
    key = ident(object_key)
    objects[key] = dict(isa=isa, **values)
    return key

def ref(path, kind):
    return obj(path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="<group>")

def buildfile(name, reference, **values):
    return obj("build:" + name, "PBXBuildFile", fileRef=reference, **values)

project_id = ident("project")
local_package = obj("local-package", "XCLocalSwiftPackageReference", relativePath="Packages/CalendarShareKit")
auth_package = obj("auth-package", "XCRemoteSwiftPackageReference", repositoryURL="https://github.com/openid/AppAuth-iOS.git", requirement={"kind": "exactVersion", "version": "1.7.6"})
base = ref("Configuration/Base.xcconfig", "text.xcconfig")
refs = {str(p.relative_to(ROOT)): ref(str(p.relative_to(ROOT)), "sourcecode.swift")
        for folder in ("App", "MessagesExtension", "Support") for p in sorted((ROOT / folder).glob("*.swift"))}
products = {}
for name, ext, kind in [("CalendarShare", "app", "wrapper.application"), ("CalendarShareMessages", "appex", "wrapper.app-extension")]:
    products[name] = obj("product:" + name, "PBXFileReference", explicitFileType=kind, includeInIndex=0, path=name + "." + ext, sourceTree="BUILT_PRODUCTS_DIR")
product_group = obj("products", "PBXGroup", children=list(products.values()), name="Products", sourceTree="<group>")
main_group = obj("main", "PBXGroup", children=[base, *refs.values(), product_group], sourceTree="<group>")

def configs(name, settings, use_base=False):
    ids = []
    for mode in ("Debug", "Release"):
        bs = dict(settings)
        bs.update(SWIFT_OPTIMIZATION_LEVEL="-Onone" if mode == "Debug" else "-O", DEBUG_INFORMATION_FORMAT="dwarf" if mode == "Debug" else "dwarf-with-dsym")
        if mode == "Debug":
            bs["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
            bs["ENABLE_TESTABILITY"] = "YES"
        extra = {"baseConfigurationReference": base} if use_base else {}
        ids.append(obj(name + mode, "XCBuildConfiguration", buildSettings=bs, name=mode, **extra))
    return obj(name + "configs", "XCConfigurationList", buildConfigurations=ids, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")

project_configs = configs("project", {
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
    "SUPPORTS_MACCATALYST": "NO", "MARKETING_VERSION": "0.0.1", "CURRENT_PROJECT_VERSION": "1",
}, True)
target_ids = []
for name, folder, bundle, is_extension in [
    ("CalendarShareMessages", "MessagesExtension", "$(MESSAGES_BUNDLE_IDENTIFIER)", True),
    ("CalendarShare", "App", "$(APP_BUNDLE_IDENTIFIER)", False),
]:
    source_files = [buildfile(name + path, r) for path, r in refs.items() if path.startswith((folder + "/", "Support/"))]
    sources = obj(name + "sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=source_files, runOnlyForDeploymentPostprocessing=0)
    package_products = []
    frameworks = []
    modules = ["CalendarDomain", "MessageCodec", "SharedStore", "AuthorizationStore", "GoogleCalendarProvider", "EventKitProvider"]
    if not is_extension:
        modules += ["AppAuth"]
    for module in modules:
        kwargs = {"package": auth_package} if module == "AppAuth" else {}
        product = obj(name + module, "XCSwiftPackageProductDependency", productName=module, **kwargs)
        package_products.append(product)
        frameworks.append(obj(name + module + "framework", "PBXBuildFile", productRef=product))
    framework_phase = obj(name + "frameworks", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=frameworks, runOnlyForDeploymentPostprocessing=0)
    resources = obj(name + "resources", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
    phases = [sources, framework_phase, resources]
    dependencies = []
    if not is_extension:
        embed = buildfile("embed-extension", products["CalendarShareMessages"], settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
        phases.append(obj("embed", "PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=[embed], name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0))
        proxy = obj("proxy", "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=ident("target:CalendarShareMessages"), remoteInfo="CalendarShareMessages")
        dependencies.append(obj("dependency", "PBXTargetDependency", target=ident("target:CalendarShareMessages"), targetProxy=proxy))
    settings = {"PRODUCT_BUNDLE_IDENTIFIER": bundle, "PRODUCT_NAME": "$(TARGET_NAME)", "INFOPLIST_FILE": folder + "/Info.plist",
                "GENERATE_INFOPLIST_FILE": "NO", "CODE_SIGN_ENTITLEMENTS": "Configuration/CalendarShare.entitlements",
                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"] + (["@executable_path/../../Frameworks"] if is_extension else []),
                "APPLICATION_EXTENSION_API_ONLY": "YES" if is_extension else "NO", "SKIP_INSTALL": "YES" if is_extension else "NO"}
    target_ids.append(obj("target:" + name, "PBXNativeTarget", buildConfigurationList=configs(name, settings), buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, packageProductDependencies=package_products, productName=name, productReference=products[name], productType="com.apple.product-type.app-extension.messages" if is_extension else "com.apple.product-type.application"))
obj("project", "PBXProject", attributes={"LastUpgradeCheck": "1500", "TargetAttributes": {t: {"CreatedOnToolsVersion": "15.0.1"} for t in target_ids}}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group, packageReferences=[local_package, auth_package], productRefGroup=product_group, projectDirPath="", projectRoot="", targets=target_ids)

def encode(value, indent=0):
    if isinstance(value, dict):
        return "{\n" + "\n".join("\t" * (indent + 1) + json.dumps(k) + " = " + encode(v, indent + 1) + ";" for k, v in value.items()) + "\n" + "\t" * indent + "}"
    if isinstance(value, list):
        return "(" + ", ".join(encode(v, indent) for v in value) + ")"
    return str(value) if isinstance(value, int) else json.dumps(value)

project = ROOT / "CalendarShare.xcodeproj"
project.mkdir(exist_ok=True)
(project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project_id}) + "\n")
schemes = project / "xcshareddata/xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
(schemes / "CalendarShare.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident('target:CalendarShare')}" BuildableName="CalendarShare.app" BlueprintName="CalendarShare" ReferencedContainer="container:CalendarShare.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident('target:CalendarShare')}" BuildableName="CalendarShare.app" BlueprintName="CalendarShare" ReferencedContainer="container:CalendarShare.xcodeproj"/></BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')

common = {"CFBundleDevelopmentRegion": "en", "CFBundleDisplayName": "Calendar Share M0", "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)", "CFBundleInfoDictionaryVersion": "6.0", "CFBundleName": "$(PRODUCT_NAME)", "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)", "NSCalendarsFullAccessUsageDescription": "Choose calendar events to share and select where to save events you receive.", "CalendarShareAppGroup": "$(APP_GROUP_IDENTIFIER)", "CalendarShareKeychainGroup": "$(AppIdentifierPrefix)$(KEYCHAIN_GROUP_SUFFIX)", "CalendarShareSetupScheme": "$(SETUP_URL_SCHEME)", "CalendarShareGoogleClientID": "$(GOOGLE_CLIENT_ID)", "CalendarShareGoogleRedirectScheme": "$(GOOGLE_REDIRECT_SCHEME)", "CalendarShareMessageBaseURL": "$(MESSAGE_BASE_URL)"}
app = dict(common, CFBundlePackageType="APPL", LSRequiresIPhoneOS=True, UILaunchScreen={}, UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"], CFBundleURLTypes=[{"CFBundleURLName": "Setup", "CFBundleURLSchemes": ["$(SETUP_URL_SCHEME)"]}, {"CFBundleURLName": "Google OAuth", "CFBundleURLSchemes": ["$(GOOGLE_REDIRECT_SCHEME)"]}])
extension = dict(common, CFBundlePackageType="XPC!", NSExtension={"NSExtensionPointIdentifier": "com.apple.message-payload-provider", "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).MessagesViewController"})
for folder, info in [("App", app), ("MessagesExtension", extension)]:
    (ROOT / folder / "Info.plist").write_bytes(plistlib.dumps(info, sort_keys=False))
print("Generated CalendarShare.xcodeproj and target Info.plists")
