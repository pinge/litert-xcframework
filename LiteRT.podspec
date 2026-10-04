Pod::Spec.new do |spec|
  spec.name = 'LiteRT'
  spec.version = '2.2.0'
  spec.authors = 'Google Inc.'
  spec.license = { :type => 'Apache-2.0', :file => 'LICENSE' }
  spec.homepage = 'https://github.com/google-ai-edge/LiteRT'
  spec.source = {
    :http => "https://github.com/pinge/litert-xcframework/releases/download/v#{spec.version}/LiteRT.xcframeworks.zip",
    :sha256 => '5512be475b08d7673a41ff77177a17ac8531a78bc2676ad356b21136cec8a73c'
  }
  spec.summary = 'LiteRT runtime and Metal accelerator for iOS.'
  spec.cocoapods_version = '>= 1.9.0'
  spec.ios.deployment_target = '15.0'
  spec.vendored_frameworks = [
    'CLiteRT.xcframework',
    'LiteRTMetalAccelerator.xcframework'
  ]
end
