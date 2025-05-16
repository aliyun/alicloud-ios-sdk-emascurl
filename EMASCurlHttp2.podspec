Pod::Spec.new do |s|
    s.name         = "EMASCurl"
    s.version      = "1.2.1"
    s.summary      = "Aliyun EMASCurl iOS SDK with HTTP/2 support."
    s.homepage     = "https://www.aliyun.com/product/httpdns"
    s.author       = { "xiaoyu" => "yx456323@alibaba-inc.com" }

    s.platform     = :ios
    s.ios.deployment_target = '10.0'

    s.source       = { :git => "https://github.com/aliyun/alicloud-ios-sdk-emascurl.git", :tag => s.version.to_s }

    s.source_files = 'EMASCurl/*.{h,m}'

    s.public_header_files = [
      'EMASCurl/EMASCurl.h',
      'EMASCurl/EMASCurlProtocol.h'
    ]

    s.resource_bundles = {
      'EMASCAResource' => ['precompiled/cacert.pem']
    }

    s.requires_arc = true
    s.frameworks = 'Foundation'

    s.vendored_frameworks = 'precompiled/libcurl-HTTP2.xcframework'

    s.dependency 'OpenSSL-Universal', '~> 3.3.1000'

    s.xcconfig = {
      'OTHER_LDFLAGS' => '$(inherited) -ObjC -lz',
      'HEADER_SEARCH_PATHS' => '$(inherited) ${PODS_ROOT}/EMASCurlHttp2/EMASCurl'
    }
end
