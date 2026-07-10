#!/usr/bin/env bash

# 本文件提供发布脚本共享的版本读取、校验、递增和 Xcode 工程同步能力。

# 从 Xcode 工程读取唯一设置值；不同目标值不一致时拒绝继续发布。
release_read_project_setting() {
  local project_file="$1"
  local setting_name="$2"
  local values
  values="$(
    awk -v key="$setting_name" '$1 == key && $2 == "=" { gsub(/;/, "", $3); print $3 }' "$project_file" \
      | sort -u
  )"
  if [ -z "$values" ]; then
    echo "Missing $setting_name in $project_file" >&2
    return 1
  fi
  if [ "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" != "1" ]; then
    echo "Inconsistent $setting_name values: $values" >&2
    return 1
  fi
  printf '%s\n' "$values"
}

# 校验用户可见版本必须是三段纯数字语义版本。
release_validate_marketing_version() {
  local version="$1"
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# 校验构建号必须是大于零的整数。
release_validate_build_number() {
  local build_number="$1"
  [[ "$build_number" =~ ^[1-9][0-9]*$ ]]
}

# 返回下一个单调递增构建号。
release_next_build_number() {
  local build_number="$1"
  release_validate_build_number "$build_number" || return 1
  printf '%s\n' "$((build_number + 1))"
}

# 同步工程中主应用和 Widget 的所有语义版本与构建号设置。
release_update_project_versions() {
  local project_file="$1"
  local marketing_version="$2"
  local build_number="$3"
  release_validate_marketing_version "$marketing_version" || {
    echo "Invalid marketing version: $marketing_version" >&2
    return 1
  }
  release_validate_build_number "$build_number" || {
    echo "Invalid build number: $build_number" >&2
    return 1
  }

  RELEASE_MARKETING_VERSION="$marketing_version" RELEASE_BUILD_NUMBER="$build_number" \
    /usr/bin/perl -0pi -e '
      s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $ENV{RELEASE_MARKETING_VERSION};/g;
      s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = $ENV{RELEASE_BUILD_NUMBER};/g;
    ' "$project_file"
}
