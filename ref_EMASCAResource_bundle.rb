require 'xcodeproj'

project_path = './EMASCurl.xcodeproj'
bundle_path = './out/EMASCAResource.bundle'
targets_to_update = ['EMASCurlTests', 'EMASCurlDemo']

# 打开 Xcode 项目
project = Xcodeproj::Project.open(project_path)

# 找到 main group
main_group = project.main_group

# 检查文件引用是否已经存在于 main group
file_ref = main_group.files.find { |file| file.path == bundle_path }
if file_ref.nil?
  file_ref = main_group.new_file(bundle_path)
  puts "Added new file reference for #{bundle_path} to main group."
else
  puts "File reference for #{bundle_path} already exists in main group."
end

targets_to_update.each do |target_name|
  # 查找目标
  target = project.targets.find { |t| t.name == target_name }

  if target.nil?
    puts "Target '#{target_name}' not found."
    next
  else
    puts "Found target '#{target_name}'."
  end

  # 列出所有构建阶段以确认结构
  puts "Available build phases in target '#{target_name}':"
  target.build_phases.each do |build_phase|
    puts "  - #{build_phase.display_name}"
  end

  # 找到 "Copy Bundle Resources" 构建阶段
  copy_resources_phase = target.build_phases.find { |bp| bp.display_name == 'Resources' }

  if copy_resources_phase.nil?
    puts "'Copy Bundle Resources' build phase not found in target '#{target_name}'."
    next
  else
    puts "Found 'Copy Bundle Resources' build phase."
  end

  # 检查文件引用是否已经添加到 "Copy Bundle Resources" 构建阶段
  unless copy_resources_phase.files_references.include?(file_ref)
    copy_resources_phase.add_file_reference(file_ref)
    puts "Added #{bundle_path} to #{target_name}'s 'Copy Bundle Resources' build phase."
  else
    puts "#{bundle_path} is already added to the 'Copy Bundle Resources' build phase for target '#{target_name}'."
  end
end

# 保存项目更改
project.save

puts "Successfully updated project."