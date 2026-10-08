#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint coproduct_paywall.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'coproduct_paywall'
  s.version          = '0.1.0'
  s.summary          = 'Paywall display and Apple Pay purchases for the Coproduct Flutter SDK.'
  s.description      = <<-DESC
Renders a Coproduct server-driven paywall and completes its purchase through StoreKit2 (Apple Pay).
                       DESC
  s.homepage         = 'https://coproduct.app'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Coproduct' => 'nathan@coproduct.app' }
  s.module_name      = 'coproduct_paywall'

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
