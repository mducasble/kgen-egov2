platform :ios, '17.0'

use_frameworks! :linkage => :static

project 'EgoCapture.xcodeproj'

target 'EgoCapture' do
  pod 'MediaPipeTasksVision'
end

# MediaPipe ships as a static binary inside `MediaPipeTasksCommon.framework`
# (no `lib` prefix), which Xcode's modern linker can't resolve via `-l<Name>`.
# Patch the generated xcconfigs to link as frameworks instead of libraries.
post_install do |installer|
  mediapipe_targets = %w[MediaPipeTasksCommon MediaPipeTasksVision]

  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |config|
      config.build_settings['ENABLE_USER_SCRIPT_SANDBOXING'] = 'NO'
    end
  end

  installer.aggregate_targets.each do |aggregate|
    aggregate.xcconfigs.each do |config_name, _config_file|
      xcconfig_path = aggregate.xcconfig_path(config_name)
      next unless File.exist?(xcconfig_path)

      contents = File.read(xcconfig_path)

      # Rewrite `-l"Name"` (or `-lName`) into `-framework "Name"` for MediaPipe.
      mediapipe_targets.each do |name|
        contents = contents.gsub(/-l\s*"?#{Regexp.escape(name)}"?/, %(-framework "#{name}"))
      end

      # Ensure the extracted .framework dirs are on the framework search path.
      fw_line = contents[/^FRAMEWORK_SEARCH_PATHS\s*=[^\n]*/] || ''
      extras = mediapipe_targets.map { |n| %("${PODS_XCFRAMEWORKS_BUILD_DIR}/#{n}") }
      missing = extras.reject { |p| fw_line.include?(p) }
      unless missing.empty?
        contents = contents.sub(/^(FRAMEWORK_SEARCH_PATHS\s*=[^\n]*)/) do
          "#{Regexp.last_match(1)} #{missing.join(' ')}"
        end
      end

      File.write(xcconfig_path, contents)
    end
  end
end
