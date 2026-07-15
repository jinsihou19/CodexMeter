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

# 把指定类型的 Conventional Commits 追加为发布说明分组；无匹配时不生成空标题。
release_append_notes_section() {
  local repository_path="$1"
  local revision_range="$2"
  local output_file="$3"
  local title="$4"
  local pattern="$5"
  local entries
  entries="$(
    git -C "$repository_path" log "$revision_range" --no-merges \
      --format='- %s (`%h`)' --extended-regexp --grep="$pattern" \
      | sed -E 's/^- [a-z]+(\([^)]*\))?!?:[[:space:]]*/- /'
  )"
  if [ -n "$entries" ]; then
    printf '## %s\n\n%s\n\n' "$title" "$entries" >> "$output_file"
  fi
}

# 按提交类型生成发布说明，未遵循约定的提交收入“其他变更”。
release_write_notes() {
  local repository_path="$1"
  local revision_range="$2"
  local output_file="$3"
  local previous_tag="$4"
  local release_tag="$5"
  local repository_slug="$6"
  local other_entries

  printf '# 变更内容\n\n' > "$output_file"
  release_append_notes_section "$repository_path" "$revision_range" "$output_file" "新功能" '^feat(\([^)]*\))?!?:[[:space:]]'
  release_append_notes_section "$repository_path" "$revision_range" "$output_file" "问题修复" '^fix(\([^)]*\))?!?:[[:space:]]'
  release_append_notes_section "$repository_path" "$revision_range" "$output_file" "性能优化" '^perf(\([^)]*\))?!?:[[:space:]]'
  release_append_notes_section "$repository_path" "$revision_range" "$output_file" "代码调整" '^(refactor|style)(\([^)]*\))?!?:[[:space:]]'
  release_append_notes_section "$repository_path" "$revision_range" "$output_file" "文档" '^docs(\([^)]*\))?!?:[[:space:]]'
  release_append_notes_section "$repository_path" "$revision_range" "$output_file" "工程维护" '^(test|build|ci|chore|revert)(\([^)]*\))?!?:[[:space:]]'

  other_entries="$(
    git -C "$repository_path" log "$revision_range" --no-merges --format='- %s (`%h`)' \
      | grep -Ev '^- (feat|fix|perf|refactor|style|docs|test|build|ci|chore|revert)(\([^)]*\))?!?:[[:space:]]' \
      || true
  )"
  if [ -n "$other_entries" ]; then
    printf '## 其他变更\n\n%s\n\n' "$other_entries" >> "$output_file"
  fi

  if [ -n "$previous_tag" ]; then
    printf '**完整变更记录**: https://github.com/%s/compare/%s...%s\n' \
      "$repository_slug" "$previous_tag" "$release_tag" >> "$output_file"
  fi
}
