#!/bin/bash
# author: wayne
# ==========================================
# 🧩 Git Hooks 一键初始化脚本
# 适用于已存在的 Git 仓库
# 禁止 main 分支直接 push + PR 自动创建
# 支持 macOS/Linux/Windows
# ==========================================

set -e

# 检查是否在 Git 仓库内
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ 当前目录不是 Git 仓库，请进入项目根目录执行此脚本"
    exit 1
fi

# 获取仓库根目录
ROOT_DIR=$(git rev-parse --show-toplevel)
HOOKS_DIR="$ROOT_DIR/.git/hooks"
CUSTOM_HOOKS="$ROOT_DIR/.githooks"

echo "🧱 仓库根目录: $ROOT_DIR"
echo "🪝 Hooks 目录: $CUSTOM_HOOKS"
echo ""

# 检查 .githooks 是否存在
if [ ! -d "$CUSTOM_HOOKS" ]; then
    echo "📁 未找到 $CUSTOM_HOOKS 目录，正在创建..."
    mkdir -p "$CUSTOM_HOOKS"
fi

# 确保 .githooks 被 git 忽略
GITIGNORE_FILE="$ROOT_DIR/.gitignore"
if ! grep -q "^\.githooks/$" "$GITIGNORE_FILE" 2>/dev/null; then
    echo "📝 添加 .githooks/ 到 .gitignore..."
    echo "" >> "$GITIGNORE_FILE"
    echo "# Git Hooks (本地配置，不提交到仓库)" >> "$GITIGNORE_FILE"
    echo ".githooks/" >> "$GITIGNORE_FILE"
    echo "   ✓ 已更新 .gitignore"
fi

# 设置 core.hooksPath
echo "⚙️ 设置 Git hooksPath..."
git config core.hooksPath "$CUSTOM_HOOKS"

# ==========================================
# 创建 .git/hooks 中的自动恢复钩子
# ==========================================

# 创建 post-checkout 钩子（自动保持 hooks 生效）
cat << 'EOF' > "$HOOKS_DIR/post-checkout"
#!/bin/bash
ROOT_DIR=$(git rev-parse --show-toplevel)
git config core.hooksPath "$ROOT_DIR/.githooks" >/dev/null 2>&1
chmod +x "$ROOT_DIR/.githooks/"* 2>/dev/null
EOF

# 创建 post-merge 钩子（拉取或合并后保持生效）
cat << 'EOF' > "$HOOKS_DIR/post-merge"
#!/bin/bash
ROOT_DIR=$(git rev-parse --show-toplevel)
git config core.hooksPath "$ROOT_DIR/.githooks" >/dev/null 2>&1
chmod +x "$ROOT_DIR/.githooks/"* 2>/dev/null
EOF

chmod +x "$HOOKS_DIR/post-checkout" "$HOOKS_DIR/post-merge"

echo "✅ 已创建自动恢复钩子："
echo "   - $HOOKS_DIR/post-checkout"
echo "   - $HOOKS_DIR/post-merge"
echo ""

# ==========================================
# 创建 .githooks 中的自定义钩子
# ==========================================

# 1. pre-commit：仅提示，不阻止（允许在 main 上 commit）
cat << 'EOF' > "$CUSTOM_HOOKS/pre-commit"
#!/bin/bash
# ==========================================
# 💡 提示：main 分支 commit 警告
# ==========================================

# 定义受保护的分支列表
PROTECTED_BRANCHES=("main" "master")

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 检查当前分支是否在保护列表中
is_protected=false
for branch in "${PROTECTED_BRANCHES[@]}"; do
    if [ "$CURRENT_BRANCH" = "$branch" ]; then
        is_protected=true
        break
    fi
done

# 如果是受保护分支，给出警告（但不阻止 commit）
if [ "$is_protected" = true ]; then
    echo ""
    echo "⚠️  警告：你正在 $CURRENT_BRANCH 分支上提交"
    echo "   commit 将被允许，但 push 时会自动转移到新分支"
    echo ""
fi

exit 0
EOF

echo "💡 已创建 pre-commit 钩子（仅警告，不阻止）"
echo ""

# ==========================================
# 2. pre-push：禁止 main 分支 push + 自动转移到临时分支
# ==========================================

cat << 'EOF' > "$CUSTOM_HOOKS/pre-push"
#!/bin/bash
# ==========================================
# 🚀 pre-push Hook - Main 分支强制保护
# 禁止直接 push main，自动转移到临时分支并创建 PR
# 支持 macOS/Linux/Windows (Git Bash)
# ==========================================

PROTECTED_BRANCHES=("main" "master")
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 检测操作系统
detect_os() {
    case "$(uname -s)" in
        Darwin*)    echo "mac" ;;
        Linux*)     echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)          echo "unknown" ;;
    esac
}

OS_TYPE=$(detect_os)

# 检查 gh CLI
check_gh_cli() {
    command -v gh &> /dev/null
}

# 检查认证
check_gh_auth() {
    gh auth status &> /dev/null
}

# 安装提示
show_install_instructions() {
    echo ""
    echo "📦 GitHub CLI (gh) 未安装"
    echo ""
    case "$OS_TYPE" in
        mac)
            echo "   macOS: brew install gh"
            ;;
        linux)
            echo "   Linux: sudo apt install gh"
            ;;
        windows)
            echo "   Windows: winget install --id GitHub.cli"
            ;;
    esac
    echo ""
    echo "   官网: https://docs.github.com/zh/github-cli/github-cli/quickstart"
    echo ""
}

# 生成预合并分支名
generate_branch_name() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local user_name=$(git config user.name 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' ' | cut -c1-8)
    
    # 如果无法获取用户名，使用系统用户名
    if [ -z "$user_name" ]; then
        user_name=$(whoami | cut -c1-8)
    fi
    
    # 获取最后一次 merge 的分支名
    local last_merged_branch=""
    
    # 方法1: 从 git log 中查找最近的 merge commit 信息
    last_merged_branch=$(git log --merges --oneline -1 --pretty=format:"%s" 2>/dev/null | \
        sed -n "s/.*Merge branch '\([^']*\)'.*/\1/p" | \
        head -1 | \
        tr '/' '-' | \
        cut -c1-15)
    
    # 方法2: 如果方法1失败，尝试从 reflog 获取
    if [ -z "$last_merged_branch" ]; then
        last_merged_branch=$(git reflog --grep="merge" -1 --pretty=format:"%gs" 2>/dev/null | \
            sed -n "s/.*merge \([^:]*\):.*/\1/p" | \
            tr '/' '-' | \
            cut -c1-15)
    fi
    
    # 方法3: 如果还是获取不到，使用随机后缀作为后备
    if [ -z "$last_merged_branch" ]; then
        last_merged_branch=$(openssl rand -hex 3 2>/dev/null || printf "%06d" $((RANDOM % 1000000)))
    fi
    
    # 清理分支名，确保符合 Git 分支命名规范
    last_merged_branch=$(echo "$last_merged_branch" | sed 's/[^a-zA-Z0-9_-]//g')
    
    echo "feat/premerge-${user_name}-${timestamp}-${last_merged_branch}"
}

# 检查是否是merge操作（包括fast-forward merge）
is_merge_operation() {
    local unpushed_commits="$1"
    if [ "$unpushed_commits" -eq 0 ]; then
        return 1
    fi
    
    # 方法1: 检查未推送的提交中是否包含merge提交
    local has_merge_commit=false
    if git rev-parse @{u} > /dev/null 2>&1; then
        # 有上游分支，检查@{u}..HEAD范围内的merge提交
        if [ "$(git rev-list @{u}..HEAD --merges --count 2>/dev/null)" != "0" ]; then
            has_merge_commit=true
        fi
    else
        # 没有上游分支，检查所有提交中的merge提交
        if [ "$(git rev-list HEAD --merges --count 2>/dev/null)" != "0" ]; then
            has_merge_commit=true
        fi
    fi
    
    # 方法2: 检查是否是fast-forward merge
    # 通过检查最近的reflog条目来判断是否刚执行了merge操作
    local recent_merge=false
    if git reflog -1 --pretty=format:"%gs" 2>/dev/null | grep -q "merge"; then
        recent_merge=true
    fi
    
    # 如果有merge提交或者最近执行了merge操作，认为是merge操作
    [ "$has_merge_commit" = true ] || [ "$recent_merge" = true ]
}


# ========== 主逻辑 ==========
main() {
    # 检查当前是否在受保护分支
    is_protected=false
    protected_branch=""
    for branch in "${PROTECTED_BRANCHES[@]}"; do
        if [ "$CURRENT_BRANCH" = "$branch" ]; then
            is_protected=true
            protected_branch="$branch"
            break
        fi
    done
    
    # 如果在受保护分支（main/master），执行特殊逻辑
    if [ "$is_protected" = true ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🛡️  检测到 $CURRENT_BRANCH 分支 - 启动保护流程"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # 检查是否有未推送的提交（相对于远程分支）
        if ! git rev-parse @{u} > /dev/null 2>&1; then
            # 没有上游分支
            echo "⚠️  当前分支没有远程跟踪分支"
            
            # 检查是否有提交
            if [ $(git rev-list --count HEAD) -eq 0 ]; then
                echo "❌ 当前分支没有任何提交"
                exit 1
            fi
            
            # 有提交但没有上游，说明本地有新提交
            UNPUSHED_COMMITS=$(git rev-list --count HEAD)
            echo "📊 检测到 $UNPUSHED_COMMITS 个本地提交"
        else
            # 有上游分支，检查本地领先的提交数
            UNPUSHED_COMMITS=$(git rev-list @{u}..HEAD --count 2>/dev/null || echo "0")
            
            if [ "$UNPUSHED_COMMITS" -eq 0 ]; then
                echo "✅ 没有新的提交需要推送，允许 push（可能是 pull 或 merge 后的同步）"
                exit 0
            fi
            
            echo "📊 检测到 $UNPUSHED_COMMITS 个未推送的提交"
        fi
        
        # 检查是否是merge操作（包括fast-forward merge）
        if is_merge_operation "$UNPUSHED_COMMITS"; then
            echo "🔀 检测到merge操作，这可能是从其他分支合并的更改"
            echo "🚫 禁止直接push merge结果到 $CURRENT_BRANCH 分支"
            echo "🔄 正在自动转移提交到临时分支..."
        else
            echo "📝 检测到直接在 $CURRENT_BRANCH 分支上的提交"
            echo ""
            echo "🚫 禁止直接推送到 $CURRENT_BRANCH 分支"
            echo ""
            echo "💡 如果你确定要直接推送到 $CURRENT_BRANCH 分支，请使用："
            echo "   git push --no-verify"
            echo ""
            echo "⚠️  注意：这将绕过分支保护，请谨慎使用！"
            echo "📋 推荐做法：创建功能分支后通过PR合并"
            exit 1
        fi
        
        echo ""
        
        # 生成临时分支名
        NEW_BRANCH=$(generate_branch_name)
        echo "🌿 生成临时分支: $NEW_BRANCH"
        echo ""
        
        # 保存当前 HEAD 位置
        CURRENT_HEAD=$(git rev-parse HEAD)
        
        # 创建新分支（基于当前 HEAD）
        if ! git checkout -b "$NEW_BRANCH" 2>/dev/null; then
            echo "❌ 创建分支失败"
            exit 1
        fi
        
        echo "✅ 已切换到临时分支: $NEW_BRANCH"
        echo "🚀 正在推送到远程..."
        echo ""
        
        # 推送到远程（设置上游）
        if ! git push -u origin "$NEW_BRANCH" 2>&1; then
            echo ""
            echo "❌ 推送失败，正在恢复到 $protected_branch..."
            git checkout "$protected_branch" 2>/dev/null
            git branch -D "$NEW_BRANCH" 2>/dev/null
            exit 1
        fi
        
        echo ""
        echo "✅ 推送成功！"
        echo ""
        
        # 切回原分支（保持原状态）
        echo "🔄 切回 $protected_branch 分支..."
        git checkout "$protected_branch" 2>/dev/null
        echo "✅ 已切回 $protected_branch 分支"
        echo ""
        
        # 检查 gh CLI 并创建 PR
        if ! check_gh_cli; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "📋 下一步操作："
            echo "   1. 手动创建 PR: $NEW_BRANCH → $protected_branch"
            echo "   2. 或安装 gh CLI 后执行: gh pr create --web"
            show_install_instructions
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            exit 1
        fi
        
        if ! check_gh_auth; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "⚠️  GitHub CLI 未登录"
            echo ""
            echo "请先执行: gh auth login"
            echo ""
            echo "或手动创建 PR: $NEW_BRANCH → $protected_branch"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            exit 1
        fi
        
        # 创建 PR
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🚀 正在打开浏览器创建 PR..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🌿 从: $NEW_BRANCH"
        echo "🎯 到: $protected_branch"
        echo ""
        
        # 切换到新分支来创建 PR
        git checkout "$NEW_BRANCH" 2>/dev/null
        
        # 使用 --web 打开浏览器，base 指定目标分支
        if gh pr create --web --base "$protected_branch" 2>/dev/null; then
            echo "✅ 已在浏览器中打开 PR 创建页面"
        else
            echo "⚠️  无法自动打开 PR 页面"
            echo "💡 请手动执行: gh pr create --web --base $protected_branch"
        fi
        
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✨ 完成！当前在分支: $NEW_BRANCH"
        echo ""
        echo "💡 提示："
        echo "   • 你的提交已转移到 $NEW_BRANCH 并推送"
        echo "   • $protected_branch 分支保持原状态"
        echo "   • 请在浏览器中完成 PR 创建"
        echo "   • PR 合并后可删除临时分支"
        echo "   • 如需切回主分支: git checkout $protected_branch"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # 阻止原始 push 操作
        exit 1
    fi
    
    # 非受保护分支：正常 push
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌿 当前分支: $CURRENT_BRANCH"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ 允许推送到功能分支"
    echo ""
    echo "💡 提示：推送完成后，你可以手动创建 PR："
    echo "   gh pr create --web"
    echo ""
    exit 0
}

main
exit 0
EOF

chmod +x "$CUSTOM_HOOKS/pre-push"

echo "🚀 已创建增强版 pre-push 钩子："
echo "   - $CUSTOM_HOOKS/pre-push"
echo "   - 禁止直接 push main/master 分支"
echo "   - 自动创建 feat/premerge-user-timestamp-lastmerged 临时分支"
echo "   - 自动推送并打开 PR 页面"
echo "   - 支持 macOS/Linux/Windows"
echo ""

# 为所有自定义 hooks 授权
chmod +x "$CUSTOM_HOOKS"/* 2>/dev/null || true

# ==========================================
# 验证配置
# ==========================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
CURRENT_PATH=$(git config core.hooksPath)
if [ "$CURRENT_PATH" == "$CUSTOM_HOOKS" ]; then
    echo "🎉 核心配置验证通过"
    echo "   core.hooksPath = $CURRENT_PATH"
else
    echo "⚠️  未成功设置 core.hooksPath，请检查 Git 配置"
fi

echo ""
echo "✨ 初始化完成！已启用以下功能："
echo "   ✓ 自定义 hooks 目录管理"
echo "   ✓ 切换分支/合并后自动恢复配置"
echo "   ✓ ✅ 允许 merge 到 main 分支（PR 合并）"
echo "   ✓ 🚫 禁止在 main 分支直接 push"
echo "   ✓ 🆕 自动创建临时分支 feat/premerge-user-timestamp-lastmerged"
echo "   ✓ 🆕 自动推送并打开 PR 页面"
echo "   ✓ 🆕 main 分支保持不变"
echo "   ✓ 跨平台支持（macOS/Linux/Windows）"
echo ""
echo "📌 使用场景："
echo ""
echo "   ✅ 允许的操作："
echo "      • git checkout main && git pull"
echo "      • git checkout main && git merge feature-branch (通过 PR)"
echo "      • 在 main 分支上 commit（会有警告提示）"
echo "      • git push --no-verify (强制推送直接修改)"
echo ""
echo "   🚫 禁止的操作："
echo "      • git checkout main && git commit && git push"
echo "        → 直接修改：提示使用 --no-verify 强制推送"
echo "        → merge修改：自动转移到临时分支并创建 PR"
echo ""
echo "   🔄 自动流程（仅限merge提交）："
echo "      1. 在 main 上执行 git push（包含merge提交）"
echo "      2. 自动创建 feat/premerge-user-YYYYMMDD_HHMMSS-lastmerged"
echo "      3. 将本地新提交转移到临时分支"
echo "      4. 推送临时分支到远程"
echo "      5. 切回 main 分支（保持原状态）"
echo "      6. 打开浏览器创建 PR"
echo ""
echo "💡 注意事项："
echo "   • PR 功能需要 GitHub CLI: https://github.com/cli/cli"
echo "   • 首次使用需执行: gh auth login"
echo "   • 如需绕过（不推荐）: git push --no-verify"
echo ""
echo "🔧 快速安装 GitHub CLI："
echo "   macOS:   brew install gh"
echo "   Linux:   sudo apt install gh"
echo "   Windows: winget install --id GitHub.cli"
echo ""
echo "—— Git Hooks 初始化完成 ✅"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
