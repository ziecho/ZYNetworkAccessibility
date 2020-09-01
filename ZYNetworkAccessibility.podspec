#
#  Be sure to run `pod spec lint ZYNetworkAccessibility.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see https://guides.cocoapods.org/syntax/podspec.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |spec|

  # ―――  Spec Metadata  ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  These will help people to find your library, and whilst it
  #  can feel like a chore to fill in it's definitely to your advantage. The
  #  summary should be tweet-length, and the description more in depth.
  #

  spec.name         = "ZYNetworkAccessibility"
  spec.version      = "0.0.1"
  spec.summary      = "ZYNetworkAccessibility 提供了检测帮忙开发者引导用户打开网络权限"

  # This description is used to generate tags and improve search results.
  #   * Think: What does it do? Why did you write it? What is the focus?
  #   * Try to keep it short, snappy and to the point.
  #   * Write the description between the DESC delimiters below.
  #   * Finally, don't worry about the indent, CocoaPods strips it!
  spec.description  = <<-DESC
                      ZYNetworkAccessibility 提供了检测帮忙开发者引导用户打开网络权限
                   DESC

  spec.homepage     = "https://github.com/ziecho/ZYNetworkAccessibility"

  spec.license      = "MIT"
  # spec.license      = { :type => "MIT", :file => "FILE_LICENSE" }

  spec.author             = { "ziecho" => "ziezheng@gmail.com" }
  spec.platform     = :ios, "10.0"
  spec.source       = { :git => "https://github.com/ziecho/ZYNetworkAccessibility.git", :tag => "#{spec.version}" }
  spec.source_files  = "ZYNetworkAccessibility/**/*.{h,m}"

end
