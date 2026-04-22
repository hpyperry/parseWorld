#!/usr/bin/env ruby

require "fileutils"
require "xcodeproj"

ROOT = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "copyWorld.xcodeproj")
SCHEME_PATH = File.join(PROJECT_PATH, "xcshareddata", "xcschemes", "copyWorld.xcscheme")

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH)
project.root_object.attributes["LastUpgradeCheck"] = "2640"
project.root_object.attributes["LastSwiftUpdateCheck"] = "2640"

app_target = project.new_target(:application, "copyWorld", :osx, "14.0")
test_target = project.new_target(:unit_test_bundle, "copyWorldTests", :osx, "14.0")
test_target.add_dependency(app_target)

sources_group = project.main_group.find_subpath("Sources/copyWorld", true)
tests_group = project.main_group.find_subpath("Tests/copyWorldTests", true)
resources_group = project.main_group.find_subpath("copyWorld/Resources", true)

Dir.glob(File.join(ROOT, "Sources/copyWorld/*.swift")).sort.each do |path|
  ref = sources_group.new_file(path)
  app_target.source_build_phase.add_file_reference(ref)
end

Dir.glob(File.join(ROOT, "Tests/copyWorldTests/*.swift")).sort.each do |path|
  ref = tests_group.new_file(path)
  test_target.source_build_phase.add_file_reference(ref)
end

assets_ref = resources_group.new_file(File.join(ROOT, "copyWorld/Resources/Assets.xcassets"))
app_target.resources_build_phase.add_file_reference(assets_ref)
resources_group.new_file(File.join(ROOT, "copyWorld/Resources/Info.plist"))

app_target.build_configurations.each do |config|
  config.build_settings["INFOPLIST_FILE"] = "copyWorld/Resources/Info.plist"
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.copyworld.clipboard"
  config.build_settings["CURRENT_PROJECT_VERSION"] = "1"
  config.build_settings["MARKETING_VERSION"] = "0.1.0"
  config.build_settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
  config.build_settings["SWIFT_VERSION"] = "5.0"
  config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "14.0"
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  config.build_settings["LD_RUNPATH_SEARCH_PATHS"] = ["$(inherited)", "@executable_path/../Frameworks"]
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "NO"
  config.build_settings["ENABLE_APP_SANDBOX"] = "NO"
  config.build_settings["ENABLE_HARDENED_RUNTIME"] = "NO"
end

test_target.build_configurations.each do |config|
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.copyworld.clipboardTests"
  config.build_settings["CURRENT_PROJECT_VERSION"] = "1"
  config.build_settings["SWIFT_VERSION"] = "5.0"
  config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "14.0"
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  config.build_settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
  config.build_settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/copyWorld.app/Contents/MacOS/copyWorld"
end

project.build_configurations.each do |config|
  config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "14.0"
  config.build_settings["SWIFT_VERSION"] = "5.0"
end

project.save

FileUtils.mkdir_p(File.dirname(SCHEME_PATH))

scheme_xml = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <Scheme
     LastUpgradeVersion = "2640"
     version = "1.7">
     <BuildAction
        parallelizeBuildables = "YES"
        buildImplicitDependencies = "YES"
        buildArchitectures = "Automatic">
        <BuildActionEntries>
           <BuildActionEntry
              buildForTesting = "YES"
              buildForRunning = "YES"
              buildForProfiling = "YES"
              buildForArchiving = "YES"
              buildForAnalyzing = "YES">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{app_target.uuid}"
                 BuildableName = "copyWorld.app"
                 BlueprintName = "copyWorld"
                 ReferencedContainer = "container:copyWorld.xcodeproj">
              </BuildableReference>
           </BuildActionEntry>
           <BuildActionEntry
              buildForTesting = "YES"
              buildForRunning = "NO"
              buildForProfiling = "NO"
              buildForArchiving = "NO"
              buildForAnalyzing = "YES">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{test_target.uuid}"
                 BuildableName = "copyWorldTests.xctest"
                 BlueprintName = "copyWorldTests"
                 ReferencedContainer = "container:copyWorld.xcodeproj">
              </BuildableReference>
           </BuildActionEntry>
        </BuildActionEntries>
     </BuildAction>
     <TestAction
        buildConfiguration = "Debug"
        selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
        selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
        shouldUseLaunchSchemeArgsEnv = "YES"
        shouldAutocreateTestPlan = "YES">
        <Testables>
           <TestableReference
              skipped = "NO"
              parallelizable = "YES">
              <BuildableReference
                 BuildableIdentifier = "primary"
                 BlueprintIdentifier = "#{test_target.uuid}"
                 BuildableName = "copyWorldTests.xctest"
                 BlueprintName = "copyWorldTests"
                 ReferencedContainer = "container:copyWorld.xcodeproj">
              </BuildableReference>
           </TestableReference>
        </Testables>
     </TestAction>
     <LaunchAction
        buildConfiguration = "Debug"
        selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
        selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
        launchStyle = "0"
        useCustomWorkingDirectory = "NO"
        ignoresPersistentStateOnLaunch = "NO"
        debugDocumentVersioning = "YES"
        debugServiceExtension = "internal"
        allowLocationSimulation = "YES">
        <BuildableProductRunnable
           runnableDebuggingMode = "0">
           <BuildableReference
              BuildableIdentifier = "primary"
              BlueprintIdentifier = "#{app_target.uuid}"
              BuildableName = "copyWorld.app"
              BlueprintName = "copyWorld"
              ReferencedContainer = "container:copyWorld.xcodeproj">
           </BuildableReference>
        </BuildableProductRunnable>
     </LaunchAction>
     <ProfileAction
        buildConfiguration = "Release"
        shouldUseLaunchSchemeArgsEnv = "YES"
        savedToolIdentifier = ""
        useCustomWorkingDirectory = "NO"
        debugDocumentVersioning = "YES">
        <BuildableProductRunnable
           runnableDebuggingMode = "0">
           <BuildableReference
              BuildableIdentifier = "primary"
              BlueprintIdentifier = "#{app_target.uuid}"
              BuildableName = "copyWorld.app"
              BlueprintName = "copyWorld"
              ReferencedContainer = "container:copyWorld.xcodeproj">
           </BuildableReference>
        </BuildableProductRunnable>
     </ProfileAction>
     <AnalyzeAction
        buildConfiguration = "Debug">
     </AnalyzeAction>
     <ArchiveAction
        buildConfiguration = "Release"
        revealArchiveInOrganizer = "YES">
     </ArchiveAction>
  </Scheme>
XML

File.write(SCHEME_PATH, scheme_xml)
