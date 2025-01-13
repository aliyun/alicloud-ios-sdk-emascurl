source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/aliyun/aliyun-specs.git'

# Uncomment the next line to define a global platform for your project
platform :ios, '10.0'

target 'EMASCurlDemo' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  pod 'AlicloudHTTPDNS', '3.1.5'
  pod 'YYCache'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      end
    end
end
