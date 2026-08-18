#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint coproduct.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'coproduct'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.module_name      = 'coproduct'

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Stage prebuilt Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/stage_prebuilt.sh"',
    :execution_position => :before_compile,
    :input_files => [
      '${PODS_TARGET_SRCROOT}/stage_prebuilt.sh',
      '${PODS_TARGET_SRCROOT}/CoproductFFI.xcframework/ios-arm64/libcoproduct_ffi_frb.a',
      '${PODS_TARGET_SRCROOT}/CoproductFFI.xcframework/ios-arm64-simulator/libcoproduct_ffi_frb.a',
    ],
    :output_files => ["${PODS_CONFIGURATION_BUILD_DIR}/coproduct/libcoproduct_ffi_frb.a"],
    # Xcode skips a script phase whose outputs it considers current, which would
    # skip the architecture guard on a cached DerivedData or a platform switch.
    # Staging one file is cheap, so it always runs.
    :always_out_of_date => '1',
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    # Flutter.framework does not contain a i386 slice.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/coproduct/libcoproduct_ffi_frb.a',
  }
end
