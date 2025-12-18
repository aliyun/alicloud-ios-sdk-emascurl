source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/aliyun/aliyun-specs.git'

platform :ios, '12.0'

target 'EMASCurlDemo' do
  use_frameworks!

  pod 'AlicloudHTTPDNS', '3.2.1'
  pod 'EMASCurl', :path => './EMASCurl.podspec'
  pod 'EMASLocalProxy', :path => './EMASLocalProxy.podspec'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      end
    end
end
