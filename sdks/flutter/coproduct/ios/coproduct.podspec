#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint coproduct.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'coproduct'
  s.version          = '1.0.0'
  s.summary          = 'Feature flags and experimentation for Flutter.'
  s.description      = <<-DESC
Flutter SDK for Coproduct, a feature flag and experimentation platform.
                       DESC
  s.homepage         = 'https://coproduct.app'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Coproduct' => 'nathan@coproduct.app' }
  s.module_name      = 'coproduct'

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  # NWPathMonitor, for network_type. Declared rather than left to Swift
  # autolinking, which a consumer's linkage settings can defeat
  s.frameworks = 'Network'
  s.platform = :ios, '15.0'

  s.swift_version = '5.0'
  # The session attributes read and write UserDefaults, a required-reason API,
  # and a third-party SDK must declare its own use rather than rely on the app
  # or another dependency to. A resource bundle is how a pod ships the manifest
  s.resource_bundles = { 'coproduct_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }

  s.script_phase = {
    :name => 'Stage prebuilt Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/stage_prebuilt.sh"',
    :execution_position => :before_compile,
    :input_files => [
      '${PODS_TARGET_SRCROOT}/stage_prebuilt.sh',
      '${PODS_TARGET_SRCROOT}/CoproductFFI.xcframework/ios-arm64/libcoproduct_ffi_frb.a',
      '${PODS_TARGET_SRCROOT}/CoproductFFI.xcframework/ios-arm64_x86_64-simulator/libcoproduct_ffi_frb.a',
    ],
    :output_files => ["${PODS_CONFIGURATION_BUILD_DIR}/coproduct/libcoproduct_ffi_frb.a"],
    # Xcode skips a script phase whose outputs it considers current, which would
    # skip the architecture guard on a cached DerivedData or a platform switch.
    # Staging one file is cheap, so it always runs.
    :always_out_of_date => '1',
  }
  # This pod deliberately constrains no architectures. The simulator slice is
  # universal, so there is nothing to exclude, and an exclusion set here would
  # not hold in any case: CocoaPods writes pod xcconfig into
  # Pods-Runner.<config>.xcconfig, which a Flutter app's Debug.xcconfig includes
  # before Generated.xcconfig, and Generated.xcconfig declares the same key, so
  # the later include wins
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/coproduct/libcoproduct_ffi_frb.a',
  }
end
