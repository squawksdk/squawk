Pod::Spec.new do |s|
  s.name             = 'squawk'
  s.version          = '0.0.1'
  s.summary          = 'The iOS shake trigger for the squawk package.'
  s.description      = <<-DESC
Shake-to-report feedback for Flutter. This pod carries the native shake
trigger; everything else lives in Dart.
                       DESC
  s.homepage         = 'https://squawksdk.com'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = { 'Squawk' => 'https://squawksdk.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'squawk/Sources/squawk/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = {'squawk_privacy' => ['squawk/Sources/squawk/PrivacyInfo.xcprivacy']}
end
