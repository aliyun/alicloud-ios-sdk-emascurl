require 'xcodeproj'
require 'optparse'

# 解析命令行参数
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: script.rb [options]"

  opts.on("-t", "--type TYPE", "Specify the HTTP type (http2 or http3)") do |type|
    options[:type] = type
  end
end.parse!

# 检查传入参数
if options[:type].nil? || !['http2', 'http3'].include?(options[:type])
  puts "Please specify a valid type using --type (http2 or http3)"
  exit 1
end

# 根据传入的参数设置 xcframework_path
xcframework_path = if options[:type] == 'http2'
  './precompiled/libcurl-HTTP2.xcframework'
else
  './precompiled/libcurl-HTTP3.xcframework'
end

# 打开 Xcode 项目
project_path = './EMASCurl.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 列出所有目标以确认目标名称
puts "Available targets:"
project.targets.each do |target|
  puts "  - #{target.name}"
end

# 找到目标 "EMASCurl"
target_name = 'EMASCurl'
target = project.targets.find { |t| t.name == target_name }

if target.nil?
  puts "Target '#{target_name}' not found."
  exit 1
else
  puts "Found target '#{target_name}'."
end

# 列出所有构建阶段以确认结构
puts "Available build phases in target '#{target_name}':"
target.build_phases.each do |build_phase|
  puts "  - #{build_phase.display_name}"
end

# 找到 “Link Binary with Libraries” 构建阶段
link_build_phase = target.build_phases.find { |bp| bp.display_name == 'Frameworks' }

if link_build_phase.nil?
  puts "'Link Binary With Libraries' build phase not found in target '#{target_name}'."
  exit 1
else
  puts "Found 'Link Binary With Libraries' build phase."
end

# 找到 'Frameworks' 组
frameworks_group = project.main_group['Frameworks']

# 定义要检查和删除的路径
paths_to_remove = [
  './precompiled/libcurl-HTTP2.xcframework',
  './precompiled/libcurl-HTTP3.xcframework'
]

# 删除之前可能添加到构建阶段的 xcframework 文件
paths_to_remove.each do |path|
  file_ref = frameworks_group.files.find { |file| file.path == path }
  if file_ref && link_build_phase.files_references.include?(file_ref)
    puts "Removing #{path} from #{target_name}'s 'Link Binary With Libraries' build phase."
    link_build_phase.remove_file_reference(file_ref)
  end
end

# 向项目添加新 xcframework 文件

# 检查文件引用是否已经存在
file_ref = frameworks_group.files.find { |file| file.path == xcframework_path }
if file_ref.nil?
  file_ref = frameworks_group.new_file(xcframework_path)
  puts "Added new file reference for #{xcframework_path} to Frameworks group."
else
  puts "File reference for #{xcframework_path} already exists in Frameworks group."
end

# 检查文件引用是否已经添加到构建阶段
unless link_build_phase.files_references.include?(file_ref)
  link_build_phase.add_file_reference(file_ref)
  puts "Added #{xcframework_path} to #{target_name}'s 'Link Binary With Libraries' build phase."
else
  puts "#{xcframework_path} is already added to the 'Link Binary With Libraries' build phase."
end

# 保存项目更改
project.save

puts "Successfully updated project."
