source 'https://github.com/CocoaPods/Specs.git'
source 'https://github.com/aliyun/aliyun-specs.git'

platform :ios, '13.0'

target 'EMASCurlDemo' do
  use_frameworks!

  pod 'AlicloudHTTPDNS', '3.2.0'
  pod 'EMASCurl', :path => './EMASCurlHttp2.podspec'
  pod 'EMASCurlWeb', :path => './EMASCurlWeb.podspec'
  pod 'YYCache'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      end
    end
end
