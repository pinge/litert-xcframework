Pod::Spec.new do |spec|
  spec.name = 'LiteRT'
  spec.version = '2.1.6'
  spec.authors = 'Google Inc.'
  spec.license = { :type => 'Apache-2.0', :file => 'LICENSE' }
  spec.homepage = 'https://github.com/google-ai-edge/LiteRT'
  spec.source = {
    :http => "https://github.com/pinge/litert-xcframework/releases/download/v#{spec.version}/LiteRT.xcframeworks.zip",
    :sha256 => '7f249994af3966446ac7fd229836c70a586549b4529320c2ebf06961808f4e36'
  }
  spec.summary = 'LiteRT runtime and Metal accelerator for iOS.'
  spec.cocoapods_version = '>= 1.9.0'
  spec.ios.deployment_target = '15.0'
  spec.vendored_frameworks = [
    'CLiteRT.xcframework',
    'LiteRTMetalAccelerator.xcframework'
  ]
end
