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
echo "🔍 正在执行 post-checkout 钩子，检查系统环境..."
ROOT_DIR=$(git rev-parse --show-toplevel)
echo "🔍 仓库根目录: $ROOT_DIR"
echo "🔍 正在设置 core.hooksPath"
git config core.hooksPath "$ROOT_DIR/.githooks" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "🔍 设置 core.hooksPath 成功"
else
    echo "🔍 设置 core.hooksPath 失败"
fi
chmod +x "$ROOT_DIR/.githooks/"* 2>/dev/null
EOF

# 创建 post-merge 钩子（拉取或合并后保持生效）
cat << 'EOF' > "$HOOKS_DIR/post-merge"
#!/bin/bash
echo "🔍 正在执行 post-merge 钩子，检查系统环境..."
ROOT_DIR=$(git rev-parse --show-toplevel)
echo "🔍 仓库根目录: $ROOT_DIR"
echo "🔍 正在设置 core.hooksPath"
git config core.hooksPath "$ROOT_DIR/.githooks" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "🔍 设置 core.hooksPath 成功"
else
    echo "🔍 设置 core.hooksPath 失败"
fi
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

# 1. pre-commit：检查dev分支merge + 主分支提示
cat << 'EOF' > "$CUSTOM_HOOKS/pre-commit"
#!/bin/bash
# ==========================================
# 🚫 pre-commit Hook - 检查dev分支merge + 主分支提示
# 检查是否刚刚执行了从dev分支的fast-forward merge
# ==========================================

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 首先检查是否刚刚执行了从dev分支的merge（包括fast-forward）
echo ""
echo "🔍 检查是否存在dev分支的merge操作..."

# 检查最近的reflog条目
RECENT_REFLOG=$(git reflog -1 --pretty=format:"%gs" 2>/dev/null)
echo "   最近操作: $RECENT_REFLOG"

# 只有当最近操作是从dev分支merge时才阻止
if echo "$RECENT_REFLOG" | grep -q "merge.*\bdev\b\|merge.*origin/dev"; then
    echo ""
    echo "🚫 错误：检测到从 dev 分支的 merge 操作！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  检测到刚刚从 dev 分支 merge 到 '$CURRENT_BRANCH'"
    echo "⚠️  dev 分支是开发分支，禁止将其代码 merge 到其他分支"
    echo "🔍 检测方法: latest reflog analysis"
    echo ""
    echo "💡 正确的工作流程："
    echo "   1. 撤销此次merge: git reset --hard HEAD~1"
    echo "   2. 从目标分支创建功能分支: git checkout -b feature/xxx"
    echo "   3. 在功能分支上开发并提交"
    echo "   4. 推送功能分支: git push origin feature/xxx"
    echo "   5. 创建 PR: feature/xxx → $CURRENT_BRANCH"
    echo ""
    echo "💡 如需强制绕过此限制："
    echo "   git commit --no-verify"
    echo "   ⚠️  注意：这将绕过dev分支保护，强烈不推荐！"
    echo ""
    echo "🔄 立即撤销merge："
    echo "   git reset --hard HEAD~1"
    echo ""
    echo "❌ 阻止提交操作"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
else
    echo "   ✅ 最近操作不是dev分支merge"
fi

# 检查是否有staged的更改（可能来自squash merge）
if ! git diff --cached --quiet; then
    echo "   检测到staged的更改，检查是否来自dev分支的squash merge..."
    
    # 获取staged的文件列表
    STAGED_FILES=$(git diff --cached --name-only)
    echo "   staged文件: $STAGED_FILES"
    
    # 只检查最近的一个操作，并且必须是merge操作才进行检查
    LATEST_OPERATION=$(git reflog -1 --pretty=format:"%gs" 2>/dev/null)
    echo "   最近操作: $LATEST_OPERATION"
    
    # 只有当最近的操作是merge dev时才认为是squash merge
    if echo "$LATEST_OPERATION" | grep -q "merge.*\bdev\b\|merge.*origin/dev"; then
        echo ""
        echo "🚫 错误：检测到来自 dev 分支的 squash merge！"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  检测到从 dev 分支进行的 squash merge 操作"
        echo "⚠️  dev 分支是开发分支，禁止将其代码 merge 到其他分支"
        echo "🔍 检测方法: staged changes + latest reflog analysis"
        echo ""
        echo "💡 正确的工作流程："
        echo "   1. 撤销当前更改: git reset --hard HEAD"
        echo "   2. 从目标分支创建功能分支: git checkout -b feature/xxx"
        echo "   3. 在功能分支上开发并提交"
        echo "   4. 推送功能分支: git push origin feature/xxx"
        echo "   5. 创建 PR: feature/xxx → $CURRENT_BRANCH"
        echo ""
        echo "💡 如需强制绕过此限制："
        echo "   git commit --no-verify"
        echo "   ⚠️  注意：这将绕过dev分支保护，强烈不推荐！"
        echo ""
        echo "🔄 立即撤销squash merge："
        echo "   git reset --hard HEAD"
        echo ""
        echo "❌ 阻止提交操作"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 1
    else
        echo "   ✅ 最近操作不是dev分支merge，staged更改来自正常开发"
    fi
else
    # 没有staged的更改，检查是否是fast-forward merge后的状态
    if [ "$(git rev-list --count HEAD^..HEAD 2>/dev/null)" = "1" ]; then
        LATEST_COMMIT_MSG=$(git log -1 --pretty=format:"%s" 2>/dev/null)
        echo "   最新commit信息: $LATEST_COMMIT_MSG"
        
        # 检查是否包含dev分支相关的信息
        if echo "$LATEST_COMMIT_MSG" | grep -qi "dev"; then
            echo ""
            echo "🚫 错误：检测到来自 dev 分支的提交！"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "⚠️  最新的提交可能来自 dev 分支的 merge"
            echo "⚠️  dev 分支是开发分支，禁止将其代码 merge 到其他分支"
            echo ""
            echo "💡 如果这是错误检测，可以使用："
            echo "   git commit --no-verify"
            echo ""
            echo "🔄 如果确实是dev分支merge，请撤销："
            echo "   git reset --hard HEAD~1"
            echo ""
            echo "❌ 阻止提交操作"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            exit 1
        fi
    fi
fi

# 定义受保护的分支列表
PROTECTED_BRANCHES=("main" "master")

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

echo "✅ pre-commit 检查通过"
exit 0
EOF

echo "🚫 已创建增强版 pre-commit 钩子（检查dev分支merge + 主分支提示）"
echo ""

# ==========================================
# 1.5. prepare-commit-msg：阻止从dev分支的merge（在merge开始时就阻止）
# ==========================================

cat << 'EOF' > "$CUSTOM_HOOKS/prepare-commit-msg"
#!/bin/bash
# ==========================================
# 🚫 prepare-commit-msg Hook - 禁止从dev分支merge
# 在merge操作准备提交信息时检测并阻止从dev分支的merge操作
# 这个钩子在merge操作开始后、创建提交前触发
# ==========================================

# prepare-commit-msg钩子接收参数：
# $1: 包含提交信息的文件名
# $2: 提交信息的来源（可选）
# $3: commit SHA-1（可选，仅在修改提交时）

# 检查是否是merge操作
if [ ! -f ".git/MERGE_HEAD" ]; then
    # 不是merge操作，允许通过
    exit 0
fi

COMMIT_MSG_FILE="$1"
COMMIT_SOURCE="$2"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo ""
echo "🔍 检测到 merge 操作，正在检查源分支..."
echo "   当前分支: $CURRENT_BRANCH"
echo "   提交信息来源: $COMMIT_SOURCE"

# 获取MERGE_HEAD信息
MERGE_HEAD=$(cat .git/MERGE_HEAD 2>/dev/null)
echo "   MERGE_HEAD: $MERGE_HEAD"

# 解析merge源分支名
MERGE_BRANCH=""
DETECTION_METHOD=""

# 方法1: 从提交信息文件获取分支名
if [ -f "$COMMIT_MSG_FILE" ]; then
    COMMIT_MSG=$(cat "$COMMIT_MSG_FILE" 2>/dev/null)
    echo "   📝 提交信息: $COMMIT_MSG"
    
    # 提取分支名，支持多种格式
    if echo "$COMMIT_MSG" | grep -q "Merge branch"; then
        MERGE_BRANCH=$(echo "$COMMIT_MSG" | sed -n "s/.*Merge branch '\([^']*\)'.*/\1/p" | head -1)
        DETECTION_METHOD="commit message (branch)"
    elif echo "$COMMIT_MSG" | grep -q "Merge remote-tracking branch"; then
        MERGE_BRANCH=$(echo "$COMMIT_MSG" | sed -n "s/.*Merge remote-tracking branch '\([^']*\)'.*/\1/p" | head -1)
        # 移除 origin/ 前缀
        MERGE_BRANCH=$(echo "$MERGE_BRANCH" | sed 's|^origin/||')
        DETECTION_METHOD="commit message (remote-tracking)"
    fi
fi

# 方法2: 从MERGE_HEAD查找对应的分支
if [ -z "$MERGE_BRANCH" ] && [ -n "$MERGE_HEAD" ]; then
    echo "   🔍 从MERGE_HEAD查找对应的分支..."
    
    # 查找包含此commit的分支
    POSSIBLE_BRANCHES=$(git branch -r --contains "$MERGE_HEAD" 2>/dev/null | grep -v HEAD | sed 's/^[[:space:]]*//' | sed 's/origin\///')
    echo "   📝 包含MERGE_HEAD的分支: $POSSIBLE_BRANCHES"
    
    for branch in $POSSIBLE_BRANCHES; do
        if [ "$branch" = "dev" ]; then
            MERGE_BRANCH="dev"
            DETECTION_METHOD="MERGE_HEAD -> branch"
            break
        fi
    done
fi

echo "   🎯 检测结果: ${MERGE_BRANCH:-'未知'} (方法: ${DETECTION_METHOD:-'无'})"
echo ""

# 严格检查：如果检测到名为"dev"的分支，立即阻止
if [ -n "$MERGE_BRANCH" ] && [ "$MERGE_BRANCH" = "dev" ]; then
    echo "🚫 错误：禁止从 dev 分支进行 merge 操作！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  检测到正在从 'dev' 分支 merge 到 '$CURRENT_BRANCH'"
    echo "⚠️  dev 分支是开发分支，禁止将其代码 merge 到其他分支"
    echo "🔍 检测方法: $DETECTION_METHOD"
    echo ""
    echo "💡 正确的工作流程："
    echo "   1. 取消当前merge: git merge --abort"
    echo "   2. 从目标分支创建功能分支: git checkout -b feature/xxx"
    echo "   3. 在功能分支上开发并提交"
    echo "   4. 推送功能分支: git push origin feature/xxx"
    echo "   5. 创建 PR: feature/xxx → $CURRENT_BRANCH"
    echo ""
    echo "💡 如需强制绕过此限制："
    echo "   git -c core.hooksPath=/dev/null merge dev"
    echo "   ⚠️  注意：这将绕过dev分支保护，强烈不推荐！"
    echo ""
    echo "🔄 立即取消merge："
    echo "   git merge --abort"
    echo ""
    echo "❌ 阻止 merge 操作"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

# 如果无法确定merge源分支，给出警告但允许通过
if [ -z "$MERGE_BRANCH" ]; then
    echo "⚠️  警告：无法确定 merge 源分支"
    echo "💡 如果你正在从 dev 分支 merge，请立即取消: git merge --abort"
    echo ""
fi

echo "✅ merge 检查通过，允许继续"
exit 0
EOF

chmod +x "$CUSTOM_HOOKS/prepare-commit-msg"

echo "🚫 已创建 prepare-commit-msg 钩子（在merge准备提交时阻止dev分支merge）"
echo ""

# ==========================================
# 1.6. post-merge：检测并撤销dev分支的merge
# ==========================================

cat << 'EOF' > "$CUSTOM_HOOKS/post-merge"
#!/bin/bash
# ==========================================
# 🚫 post-merge Hook - 检测并撤销dev分支的merge
# 在merge完成后立即检测，如果是从dev分支merge则撤销
# ==========================================

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo ""
echo "🔍 post-merge: 检查刚完成的merge操作..."

# 检查最近的reflog条目
RECENT_REFLOG=$(git reflog -1 --pretty=format:"%gs" 2>/dev/null)
echo "   最近操作: $RECENT_REFLOG"

# 检查是否是从dev分支的merge操作
if echo "$RECENT_REFLOG" | grep -q "merge.*\bdev\b\|merge.*origin/dev"; then
    echo ""
    echo "🚫 错误：检测到从 dev 分支的 merge 操作！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  检测到刚刚从 dev 分支 merge 到 '$CURRENT_BRANCH'"
    echo "⚠️  dev 分支是开发分支，禁止将其代码 merge 到其他分支"
    echo "🔍 检测方法: post-merge reflog analysis"
    echo ""
    echo "🔄 正在自动撤销此次merge..."
    
    # 自动撤销merge
    git reset --hard HEAD~1
    
    if [ $? -eq 0 ]; then
        echo "✅ 已成功撤销从dev分支的merge"
    else
        echo "❌ 撤销失败，请手动执行: git reset --hard HEAD~1"
    fi
    
    echo ""
    echo "💡 正确的工作流程："
    echo "   1. 从目标分支创建功能分支: git checkout -b feature/xxx"
    echo "   2. 在功能分支上开发并提交"
    echo "   3. 推送功能分支: git push origin feature/xxx"
    echo "   4. 创建 PR: feature/xxx → $CURRENT_BRANCH"
    echo ""
    echo "💡 如需强制绕过此限制："
    echo "   git -c core.hooksPath=/dev/null merge dev"
    echo "   ⚠️  注意：这将绕过dev分支保护，强烈不推荐！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 不退出，因为merge已经被撤销了
    exit 0
fi

echo "✅ post-merge 检查通过"
exit 0
EOF

chmod +x "$CUSTOM_HOOKS/post-merge"

echo "🚫 已创建 post-merge 钩子（检测并自动撤销dev分支merge）"
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
    echo "   🔍 检查GitHub CLI是否安装..."
    echo "   执行命令: command -v gh"
    if command -v gh &> /dev/null; then
        echo "   ✅ GitHub CLI 已安装: $(which gh)"
        return 0
    else
        echo "   ❌ GitHub CLI 未安装"
        return 1
    fi
}

# 检查认证
check_gh_auth() {
    echo "   🔍 检查GitHub CLI认证状态..."
    echo "   执行命令: gh auth status"
    if gh auth status &> /dev/null; then
        echo "   ✅ GitHub CLI 已认证"
        return 0
    else
        echo "   ❌ GitHub CLI 未认证"
        return 1
    fi
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

# 生成预合并分支名（支持squash merge分支信息获取）
generate_branch_name() {
    echo "🔄 开始生成分支名..."
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local user_name=$(git config user.name 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d ' ' | cut -c1-8)
    
    # 如果无法获取用户名，使用系统用户名
    if [ -z "$user_name" ]; then
        user_name=$(whoami | cut -c1-8)
        echo "   📋 使用系统用户名: $user_name"
    else
        echo "   📋 使用Git用户名: $user_name"
    fi
    echo "   📅 时间戳: $timestamp"
    
    # 方法0: 优先使用已检测到的源分支信息
    echo ""
    echo "🔍 方法0: 检查预设的源分支信息"
    echo "   🖥️  系统信息: $(uname -s 2>/dev/null || echo 'Windows')"
    echo "   🐚 Shell: $SHELL"
    echo "   📋 检查环境变量 DETECTED_SOURCE_BRANCH..."
    echo "   📋 DETECTED_SOURCE_BRANCH='$DETECTED_SOURCE_BRANCH'"
    echo "   📏 长度: ${#DETECTED_SOURCE_BRANCH}"
    local squash_source_branch=""
    if [ -n "$DETECTED_SOURCE_BRANCH" ]; then
        squash_source_branch="$DETECTED_SOURCE_BRANCH"
        echo "   ✅ 使用预设的源分支信息: $squash_source_branch"
    else
        echo "   ❌ 没有预设的源分支信息，继续其他检测方法"
    fi
    
    # 方法0.1: 检查是否有staged的更改（可能来自squash merge）
    if [ -z "$squash_source_branch" ]; then
        echo ""
        echo "🔍 方法0.1: 检查staged更改（squash merge检测）"
            if ! git diff --cached --quiet; then
                echo "   📋 检测到staged的更改，可能来自squash merge"
                local staged_files=$(git diff --cached --name-only)
                echo "   📝 staged文件: $staged_files"
                
                # 检查staged的diff信息，寻找可能的分支线索
                echo "   🔍 分析staged的diff信息..."
                local diff_info=$(git diff --cached --stat 2>/dev/null)
                echo "   📝 diff统计: $diff_info"
                
                # 检查是否存在 .git/SQUASH_MSG 文件（squash merge时会创建）
                if [ -f ".git/SQUASH_MSG" ]; then
                    echo "   📋 发现 .git/SQUASH_MSG 文件"
                    local squash_msg=$(cat .git/SQUASH_MSG 2>/dev/null)
                    echo "   📝 SQUASH_MSG内容: $squash_msg"
                    # 尝试从squash消息中提取分支信息
                    squash_source_branch=$(echo "$squash_msg" | grep -o "feature/[^[:space:]]*\|[^[:space:]]*/[^[:space:]]*" | head -1)
                    echo "   🎯 从SQUASH_MSG提取的分支名: '$squash_source_branch'"
                fi
                
                # 如果SQUASH_MSG没找到，尝试从最近的分支列表获取
                if [ -z "$squash_source_branch" ]; then
                    echo "   🔍 尝试从最近访问的分支获取信息..."
                    echo "   🔍 执行命令: git reflog --pretty=format:\"%gs\" | grep \"checkout: moving from\" | head -5"
                    # 获取最近切换过的分支（除了当前分支）
                    local recent_branches=$(git reflog --pretty=format:"%gs" | grep "checkout: moving from" | head -5)
                    echo "   📋 最近的分支切换记录:"
                    if [ -n "$recent_branches" ]; then
                        echo "$recent_branches" | sed 's/^/      /'
                    else
                        echo "      (空)"
                    fi
                    
                    # 提取最近从哪个分支切换过来的
                    echo "   🔍 执行命令: sed -n 's/.*checkout: moving from \([^[:space:]]*\) to.*/\1/p'"
                    local last_branch=$(echo "$recent_branches" | head -1 | sed -n 's/.*checkout: moving from \([^[:space:]]*\) to.*/\1/p')
                    echo "   🎯 最近来源分支: '$last_branch'"
                    echo "   📏 分支名长度: ${#last_branch}"
                    
                    # 如果是feature分支，很可能就是squash merge的源分支
                    if echo "$last_branch" | grep -q "feature/\|hotfix/\|bugfix/"; then
                        squash_source_branch="$last_branch"
                        echo "   ✅ 推测squash merge源分支: $squash_source_branch"
                    fi
                fi
                
                if [ -n "$squash_source_branch" ]; then
                    echo "   ✅ 方法0.1成功: $squash_source_branch"
                else
                    echo "   ❌ 方法0.1失败: 未找到squash merge的源分支"
                fi
            else
                echo "   - 没有staged更改，跳过squash merge检测"
            fi
        fi

    # 方法1: 尝试从reflog获取最近merge的分支信息（适用于常规merge）
    echo ""
    echo "🔍 方法1: 从reflog获取最近merge的分支信息"
    local source_branch=""
    for i in 1 2 3 4 5; do
        echo "   📋 检查reflog条目 $i..."
        local reflog_msg=$(git reflog -$i --pretty=format:"%gs" 2>/dev/null | tail -1)
        echo "      内容: $reflog_msg"
        
        if echo "$reflog_msg" | grep -q "merge"; then
            echo "      ✓ 发现merge操作"
                       # 尝试提取分支名，支持多种格式
                       echo "      🔍 开始分析merge格式..."
                       if echo "$reflog_msg" | grep -q "merge branch"; then
                           echo "      📋 检测到 'merge branch' 格式"
                           source_branch=$(echo "$reflog_msg" | sed -n "s/.*merge branch '\([^']*\)'.*/\1/p" | head -1)
                           echo "      📝 提取方式: merge branch 格式"
                           echo "      🎯 sed提取结果: '$source_branch'"
                       elif echo "$reflog_msg" | grep -q "merge remote-tracking branch"; then
                           echo "      📋 检测到 'merge remote-tracking branch' 格式"
                           source_branch=$(echo "$reflog_msg" | sed -n "s/.*merge remote-tracking branch '\([^']*\)'.*/\1/p" | head -1)
                           echo "      🎯 sed提取结果(带origin): '$source_branch'"
                           # 移除 origin/ 前缀
                           source_branch=$(echo "$source_branch" | sed 's|^origin/||')
                           echo "      📝 提取方式: remote-tracking branch 格式"
                           echo "      🎯 移除origin后: '$source_branch'"
                       elif echo "$reflog_msg" | grep -q "merge.*:"; then
                           echo "      📋 检测到 'merge xxx: Fast-forward' 格式"
                           # 处理 "merge feature/test-hooks: Fast-forward" 这种格式
                           source_branch=$(echo "$reflog_msg" | sed -n 's/.*merge \([^:]*\):.*/\1/p' | head -1)
                           echo "      📝 提取方式: Fast-forward格式"
                           echo "      🎯 sed提取结果: '$source_branch'"
                       elif echo "$reflog_msg" | grep -q "merge"; then
                           echo "      📋 检测到通用 'merge' 格式"
                           # 尝试从更通用的格式提取
                           source_branch=$(echo "$reflog_msg" | sed -n 's/.*merge \([^[:space:]]*\).*/\1/p' | head -1)
                           echo "      🎯 sed提取结果(原始): '$source_branch'"
                           source_branch=$(echo "$source_branch" | sed 's|^origin/||')
                           echo "      📝 提取方式: 通用merge格式"
                           echo "      🎯 移除origin后: '$source_branch'"
                       fi
            
            echo "      🎯 提取到的分支名: ${source_branch:-'无'}"
            
            # 如果找到了有效的分支名，跳出循环
            if [ -n "$source_branch" ] && [ "$source_branch" != "main" ] && [ "$source_branch" != "master" ]; then
                echo "      ✅ 找到有效的源分支: $source_branch"
                break
            else
                echo "      ❌ 分支名无效或为主分支，继续查找..."
                source_branch=""
            fi
        else
            echo "      - 未发现merge操作"
        fi
    done
    
    if [ -n "$source_branch" ]; then
        echo "   ✅ 方法1成功: $source_branch"
    else
        echo "   ❌ 方法1失败: 未找到有效的源分支"
    fi
    
    # 方法2: 如果reflog没有找到，尝试从传统的merged branches获取
    echo ""
    echo "🔍 方法2: 从merged branches获取分支信息"
    local merged_branches=""
    if [ -z "$source_branch" ]; then
        echo "   📋 正在获取已合并的分支列表..."
        local raw_merged_branches=$(git branch --merged 2>/dev/null)
        echo "   📝 原始merged branches:"
        echo "$raw_merged_branches" | sed 's/^/      /'
        
        merged_branches=$(echo "$raw_merged_branches" | grep -iv "premerge" | grep -iv "main\|master" | \
            sed 's/^[* ]*//' | \
            tr '\n' '-' | \
            sed 's/-$//' | \
            tr '/' '-' | \
            cut -c1-30)
        
        if [ -n "$merged_branches" ]; then
            echo "   ✅ 方法2成功: $merged_branches"
        else
            echo "   ❌ 方法2失败: 未找到有效的merged branches"
        fi
    else
        echo "   ⏭️  跳过方法2: 方法1已找到源分支"
    fi
    
    # 方法3: 尝试从最近的commit message获取分支信息
    echo ""
    echo "🔍 方法3: 从最近的commit message获取分支信息"
    local commit_branch=""
    if [ -z "$source_branch" ] && [ -z "$merged_branches" ]; then
        echo "   📋 正在检查最近的commit message..."
        local recent_commit_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null)
        echo "   📝 最近的commit: $recent_commit_msg"
        
        if echo "$recent_commit_msg" | grep -qi "merge\|squash"; then
            echo "   ✓ 发现merge/squash相关的commit"
            # 尝试从commit message提取分支名
            commit_branch=$(echo "$recent_commit_msg" | sed -n 's/.*[Mm]erge.*\([a-zA-Z0-9_-]*\/[a-zA-Z0-9_-]*\).*/\1/p' | head -1)
            if [ -n "$commit_branch" ]; then
                echo "   📝 提取方式: Merge格式 (feature/xxx)"
            else
                commit_branch=$(echo "$recent_commit_msg" | sed -n 's/.*[Ff]rom \([a-zA-Z0-9_-]*\).*/\1/p' | head -1)
                if [ -n "$commit_branch" ]; then
                    echo "   📝 提取方式: From格式"
                fi
            fi
            
            if [ -n "$commit_branch" ]; then
                echo "   🎯 提取到的分支名: $commit_branch"
                echo "   ✅ 方法3成功: $commit_branch"
            else
                echo "   ❌ 无法从commit message提取分支名"
                echo "   ❌ 方法3失败: 未找到有效的分支信息"
            fi
        else
            echo "   - 未发现merge/squash相关的commit"
            echo "   ❌ 方法3失败: commit message不包含merge信息"
        fi
    else
        echo "   ⏭️  跳过方法3: 前面的方法已找到分支信息"
    fi
    
               # 决定使用哪个分支信息
               echo ""
               echo "🎯 决定最终使用的分支信息..."
               local branch_info=""
               if [ -n "$squash_source_branch" ]; then
                   branch_info="$squash_source_branch"
                   echo "   ✅ 使用方法0的结果(squash merge): $squash_source_branch"
               elif [ -n "$source_branch" ]; then
                   branch_info="$source_branch"
                   echo "   ✅ 使用方法1的结果: $source_branch"
               elif [ -n "$merged_branches" ]; then
                   branch_info="$merged_branches"
                   echo "   ✅ 使用方法2的结果: $merged_branches"
               elif [ -n "$commit_branch" ]; then
                   branch_info="$commit_branch"
                   echo "   ✅ 使用方法3的结果: $commit_branch"
               else
                   echo "   ❌ 所有方法都未找到分支信息，将使用通用格式"
               fi
    
    # 清理分支名，确保符合 Git 分支命名规范
    local final_branch_name=""
    if [ -n "$branch_info" ]; then
        echo "   🔧 正在清理分支名..."
        echo "      原始分支信息: $branch_info"
        local cleaned_branch_info=$(echo "$branch_info" | sed 's/[^a-zA-Z0-9_/-]//g' | tr '/' '-' | cut -c1-25)
        echo "      清理后分支信息: $cleaned_branch_info"
        final_branch_name="feat/premerge-${cleaned_branch_info}-${user_name}-${timestamp}"
        echo "   🎯 生成的分支名: $final_branch_name"
    else
        # 如果都没有找到，使用通用格式
        final_branch_name="feat/premerge-${user_name}-${timestamp}"
        echo "   🎯 使用通用格式分支名: $final_branch_name"
    fi
    
    echo "✅ 分支名生成完成: $final_branch_name"
    echo "$final_branch_name"
}

# 检查是否是merge操作（包括fast-forward merge和squash merge）
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
    
    # 方法2: 检查是否是fast-forward merge或squash merge
    # 通过检查最近的reflog条目来判断是否刚执行了merge操作
    local recent_merge=false
    local merge_reflog_count=0
    
    # 检查最近几个reflog条目中是否有merge操作
    for i in 1 2 3; do
        local reflog_msg=$(git reflog -$i --pretty=format:"%gs" 2>/dev/null | tail -1)
        if echo "$reflog_msg" | grep -q "merge"; then
            recent_merge=true
            merge_reflog_count=$((merge_reflog_count + 1))
            break
        fi
    done
    
    # 方法3: 检查squash merge的特征
    # squash merge会在reflog中留下merge记录，但不会创建merge commit
    local is_squash_merge=false
    if [ "$recent_merge" = true ] && [ "$has_merge_commit" = false ]; then
        # 如果有merge reflog但没有merge commit，很可能是squash merge
        # 进一步检查：squash merge通常会有大量文件变更
        local changed_files=0
        if git rev-parse @{u} > /dev/null 2>&1; then
            changed_files=$(git diff --name-only @{u}..HEAD 2>/dev/null | wc -l)
        else
            changed_files=$(git diff --name-only HEAD~1..HEAD 2>/dev/null | wc -l)
        fi
        
        # 如果文件变更数量较多（>3个文件），且最近有merge操作，判断为squash merge
        if [ "$changed_files" -gt 3 ]; then
            is_squash_merge=true
        fi
    fi
    
    # 方法4: 检查commit message是否包含merge相关信息
    local has_merge_message=false
    if git rev-parse @{u} > /dev/null 2>&1; then
        # 检查未推送的提交中是否有merge相关的commit message
        local commit_messages=$(git log @{u}..HEAD --pretty=format:"%s" 2>/dev/null)
        if echo "$commit_messages" | grep -qi "merge\|squash"; then
            has_merge_message=true
        fi
    else
        # 检查最新的commit message
        local latest_commit_msg=$(git log -1 --pretty=format:"%s" 2>/dev/null)
        if echo "$latest_commit_msg" | grep -qi "merge\|squash"; then
            has_merge_message=true
        fi
    fi
    
    # 如果满足以下任一条件，认为是merge操作：
    # 1. 有merge提交
    # 2. 最近执行了merge操作
    # 3. 检测到squash merge特征
    # 4. commit message包含merge相关信息
    [ "$has_merge_commit" = true ] || [ "$recent_merge" = true ] || [ "$is_squash_merge" = true ] || [ "$has_merge_message" = true ]
}

# 检查是否是从dev分支的merge操作（包括squash merge）
is_merge_from_dev() {
    # 方法1: 检查最近的merge reflog信息
    local recent_merge_msg=""
    for i in 1 2 3; do
        local reflog_msg=$(git reflog -$i --pretty=format:"%gs" 2>/dev/null | tail -1)
        if echo "$reflog_msg" | grep -q "merge"; then
            recent_merge_msg="$reflog_msg"
            # 检查merge信息中是否包含dev分支
            if echo "$recent_merge_msg" | grep -q "merge.*\bdev\b\|merge.*origin/dev"; then
                return 0
            fi
            break
        fi
    done
    
    # 方法2: 检查未推送的merge提交中是否来自dev分支
    local merge_commits=""
    if git rev-parse @{u} > /dev/null 2>&1; then
        merge_commits=$(git rev-list @{u}..HEAD --merges 2>/dev/null)
    else
        merge_commits=$(git rev-list HEAD --merges 2>/dev/null)
    fi
    
    if [ -n "$merge_commits" ]; then
        for commit in $merge_commits; do
            local commit_msg=$(git log -1 --pretty=format:"%s" "$commit" 2>/dev/null)
            if echo "$commit_msg" | grep -q "\bdev\b\|origin/dev"; then
                return 0
            fi
        done
    fi
    
    # 方法3: 检查squash merge的情况
    # 对于squash merge，检查最近的commit message是否包含dev相关信息
    local recent_commits=""
    if git rev-parse @{u} > /dev/null 2>&1; then
        recent_commits=$(git log @{u}..HEAD --pretty=format:"%s" 2>/dev/null)
    else
        recent_commits=$(git log -3 --pretty=format:"%s" 2>/dev/null)
    fi
    
    if [ -n "$recent_commits" ]; then
        if echo "$recent_commits" | grep -qi "\bdev\b\|origin/dev\|from.*\bdev\b\|merge.*\bdev\b"; then
            return 0
        fi
    fi
    
    # 方法4: 检查是否有大量文件变更且最近有merge操作（可能是squash merge from dev）
    if [ -n "$recent_merge_msg" ]; then
        local changed_files=0
        if git rev-parse @{u} > /dev/null 2>&1; then
            changed_files=$(git diff --name-only @{u}..HEAD 2>/dev/null | wc -l)
        else
            changed_files=$(git diff --name-only HEAD~1..HEAD 2>/dev/null | wc -l)
        fi
        
        # 如果文件变更很多（>5个），且最近有merge操作，进一步检查
        if [ "$changed_files" -gt 5 ]; then
            # 检查变更的文件路径是否符合dev分支的特征
            local changed_file_list=""
            if git rev-parse @{u} > /dev/null 2>&1; then
                changed_file_list=$(git diff --name-only @{u}..HEAD 2>/dev/null)
            else
                changed_file_list=$(git diff --name-only HEAD~1..HEAD 2>/dev/null)
            fi
            
            # 如果变更涉及多个目录或核心文件，可能是从dev分支squash merge
            local dir_count=$(echo "$changed_file_list" | sed 's|/[^/]*$||' | sort -u | wc -l)
            if [ "$dir_count" -gt 2 ]; then
                # 进一步检查git log中是否有dev相关的提交
                local all_commit_msgs=""
                if git rev-parse @{u} > /dev/null 2>&1; then
                    all_commit_msgs=$(git log @{u}..HEAD --oneline 2>/dev/null)
                else
                    all_commit_msgs=$(git log -5 --oneline 2>/dev/null)
                fi
                
                if echo "$all_commit_msgs" | grep -qi "\bdev\b"; then
                    return 0
                fi
            fi
        fi
    fi
    
    return 1
}


# ========== 主逻辑 ==========
main() {
    # 检查当前是否在受保护分支
    echo "🔍 正在检查当前分支类型..."
    echo "   当前分支: $CURRENT_BRANCH"
    echo "   受保护分支列表: ${PROTECTED_BRANCHES[*]}"
    
    is_protected=false
    protected_branch=""
    for branch in "${PROTECTED_BRANCHES[@]}"; do
        if [ "$CURRENT_BRANCH" = "$branch" ]; then
            is_protected=true
            protected_branch="$branch"
            echo "   ✅ 检测到受保护分支: $branch"
            break
        fi
    done
    
    if [ "$is_protected" = false ]; then
        echo "   ✅ 当前为功能分支，将进行功能分支检查流程"
    fi
    
    # 如果在受保护分支（main/master），执行特殊逻辑
    if [ "$is_protected" = true ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🛡️  检测到 $CURRENT_BRANCH 分支 - 启动保护流程"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        # 检查是否有未推送的提交（相对于远程分支）
        echo "🔍 正在检查本地提交状态..."
        if ! git rev-parse @{u} > /dev/null 2>&1; then
            # 没有上游分支
            echo "⚠️  当前分支没有远程跟踪分支"
            echo "📋 正在检查本地提交历史..."
            
            # 检查是否有提交
            if [ $(git rev-list --count HEAD) -eq 0 ]; then
                echo "❌ 当前分支没有任何提交"
                exit 1
            fi
            
            # 有提交但没有上游，说明本地有新提交
            UNPUSHED_COMMITS=$(git rev-list --count HEAD)
            echo "📊 检测到 $UNPUSHED_COMMITS 个本地提交（新分支）"
        else
            # 有上游分支，检查本地领先的提交数
            echo "📋 正在比较本地与远程分支..."
            UNPUSHED_COMMITS=$(git rev-list @{u}..HEAD --count 2>/dev/null || echo "0")
            
            if [ "$UNPUSHED_COMMITS" -eq 0 ]; then
                echo "✅ 没有新的提交需要推送，允许 push（可能是 pull 或 merge 后的同步）"
                exit 0
            fi
            
            echo "📊 检测到 $UNPUSHED_COMMITS 个未推送的提交"
        fi
        
        echo "🔍 正在分析提交类型..."
        
        # 检查是否是merge操作（包括fast-forward merge和squash merge）
        if is_merge_operation "$UNPUSHED_COMMITS"; then
            echo "🔀 检测到merge操作，这可能是从其他分支合并的更改（包括 squash merge）"
            
            # 检查是否是从dev分支的merge（双重保险，正常情况下pre-merge-commit已经阻止了）
            if is_merge_from_dev; then
                echo ""
                echo "🚫 错误：检测到从 dev 分支的 merge 操作！"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "⚠️  dev 分支是开发分支，禁止将其代码 merge 到其他分支"
                echo "⚠️  注意：正常情况下 pre-merge-commit 钩子应该已经阻止了这个操作"
                echo ""
                echo "💡 正确的工作流程："
                echo "   1. 从 $CURRENT_BRANCH 创建功能分支: git checkout -b feature/xxx"
                echo "   2. 在功能分支上开发并提交"
                echo "   3. 推送功能分支: git push origin feature/xxx"
                echo "   4. 创建 PR: feature/xxx → $CURRENT_BRANCH"
                echo ""
                echo "💡 如需强制绕过此限制："
                echo "   git push --no-verify"
                echo "   ⚠️  注意：这将绕过所有保护机制，强烈不推荐！"
                echo ""
                echo "🔄 如需撤销此次 merge："
                echo "   git reset --hard HEAD~1"
                echo ""
                echo "❌ 拒绝推送包含 dev 分支代码的 merge"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                exit 1
            fi
            
            echo "🚫 禁止直接push merge结果到 $CURRENT_BRANCH 分支"
            echo "🔄 正在自动转移提交到临时分支..."
        else
            echo "📝 检测到直接在 $CURRENT_BRANCH 分支上的提交"
            echo ""
            
            # 检查是否可能是squash merge的结果
            echo "🔍 检查是否为squash merge的结果..."
            echo "   🖥️  系统信息: $(uname -s 2>/dev/null || echo 'Windows')"
            echo "   🐚 Shell: $SHELL"
            echo "   📂 当前目录: $(pwd)"
            local is_squash_merge=false
            
            # 检查最近的reflog，看是否有从feature分支切换过来的记录
            echo "   🔍 执行命令: git reflog --pretty=format:\"%gs\" | grep \"checkout: moving from\" | head -1"
            local recent_checkout=$(git reflog --pretty=format:"%gs" | grep "checkout: moving from" | head -1)
            echo "   📋 最近的分支切换: '$recent_checkout'"
            echo "   📏 结果长度: ${#recent_checkout}"
            
            echo "   🔍 检查是否包含功能分支切换..."
            if echo "$recent_checkout" | grep -q "checkout: moving from feature/\|checkout: moving from hotfix/\|checkout: moving from bugfix/"; then
                echo "   ✅ 发现功能分支切换记录"
                echo "   🔍 提取源分支名..."
                echo "   🔍 执行命令: sed -n 's/.*checkout: moving from \([^[:space:]]*\) to.*/\1/p'"
                local source_branch=$(echo "$recent_checkout" | sed -n 's/.*checkout: moving from \([^[:space:]]*\) to.*/\1/p')
                echo "   🎯 检测到从功能分支切换: '$source_branch'"
                echo "   📏 源分支名长度: ${#source_branch}"
                
                # 检查提交的文件变更是否合理（不是简单的单文件修改）
                local changed_files=$(git diff --name-only HEAD~1..HEAD 2>/dev/null)
                local file_count=$(echo "$changed_files" | wc -l)
                echo "   📝 变更文件数: $file_count"
                echo "   📝 变更文件: $changed_files"
                
                # 如果从功能分支切换过来，且有合理的文件变更，很可能是squash merge
                if [ "$file_count" -ge 1 ]; then
                    echo "   ✅ 推测这是来自 $source_branch 的 squash merge"
                    is_squash_merge=true
                    
                    # 将其视为merge操作处理
                    echo "🔄 将此提交视为squash merge，转移到临时分支..."
                    
                    # 设置全局变量，供generate_branch_name函数使用
                    export DETECTED_SOURCE_BRANCH="$source_branch"
                    echo "   📋 设置源分支信息: $DETECTED_SOURCE_BRANCH"
                fi
            fi
            
            if [ "$is_squash_merge" = false ]; then
                echo "   ❌ 不是squash merge，确实是直接提交"
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
        fi
        
        echo ""
        
        # 生成临时分支名
        echo "🔄 正在生成临时分支名..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        NEW_BRANCH=$(generate_branch_name | tail -1)
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🌿 最终临时分支: $NEW_BRANCH"
        echo ""
        
        # 保存当前 HEAD 位置
        echo "📋 正在保存当前状态..."
        CURRENT_HEAD=$(git rev-parse HEAD)
        echo "   当前HEAD: $CURRENT_HEAD"
        
        # 创建新分支（基于当前 HEAD）
        echo "🔧 正在创建新分支..."
        echo "   执行命令: git checkout -b \"$NEW_BRANCH\""
        if ! git checkout -b "$NEW_BRANCH" 2>/dev/null; then
            echo "❌ 创建分支失败"
            exit 1
        fi
        
        echo "✅ 已切换到临时分支: $NEW_BRANCH"
        echo ""
        echo "🚀 正在推送到远程仓库..."
        echo "   目标: origin/$NEW_BRANCH"
        echo "   操作: git push -u origin $NEW_BRANCH"
        echo "   📋 推送前状态检查..."
        echo "      当前分支: $(git rev-parse --abbrev-ref HEAD)"
        echo "      当前HEAD: $(git rev-parse HEAD)"
        echo "      远程仓库: $(git remote -v | grep origin | head -1)"
        echo ""
        
        # 推送到远程（设置上游）
        echo "   执行命令: git push -u origin \"$NEW_BRANCH\""
        if ! git push -u origin "$NEW_BRANCH" 2>&1; then
            echo ""
            echo "❌ 推送失败，正在恢复环境..."
            echo "🔄 切换回 $protected_branch 分支..."
            git checkout "$protected_branch" 2>/dev/null
            echo "🗑️  删除临时分支 $NEW_BRANCH..."
            git branch -D "$NEW_BRANCH" 2>/dev/null
            echo "✅ 环境已恢复"
            exit 1
        fi
        
        echo ""
        echo "✅ 推送成功！"
        echo "   远程分支: origin/$NEW_BRANCH 已创建"
        echo ""
        
        # 切回原分支（保持原状态）
        echo "🔄 切回 $protected_branch 分支..."
        git checkout "$protected_branch" 2>/dev/null
        echo "✅ 已切回 $protected_branch 分支"
        echo ""
        
        # 检查 gh CLI 并创建 PR
        echo "🔍 正在检查 GitHub CLI 工具..."
        echo "   执行命令: check_gh_cli"
        if ! check_gh_cli; then
            echo "❌ GitHub CLI 未安装"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "📋 下一步操作："
            echo "   1. 手动创建 PR: $NEW_BRANCH → $protected_branch"
            echo "   2. 或安装 gh CLI 后执行: gh pr create --web"
            echo ""
            echo "💡 如需绕过 PR 流程直接推送到 $protected_branch："
            echo "   git checkout $protected_branch"
            echo "   git push --no-verify"
            echo "   ⚠️  注意：这将绕过所有保护机制，请谨慎使用！"
            show_install_instructions
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            exit 1
        fi
        
        echo "✅ GitHub CLI 已安装"
        echo "🔐 正在检查 GitHub 认证状态..."
        echo "   执行命令: check_gh_auth"
        if ! check_gh_auth; then
            echo "❌ GitHub CLI 未登录"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "⚠️  GitHub CLI 未登录"
            echo ""
            echo "请先执行: gh auth login"
            echo ""
            echo "或手动创建 PR: $NEW_BRANCH → $protected_branch"
            echo ""
            echo "💡 如需绕过 PR 流程直接推送到 $protected_branch："
            echo "   git checkout $protected_branch"
            echo "   git push --no-verify"
            echo "   ⚠️  注意：这将绕过所有保护机制，请谨慎使用！"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            exit 1
        fi
        
        echo "✅ GitHub 认证状态正常"
        
        # 创建 PR
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🚀 正在创建 Pull Request..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🌿 源分支: $NEW_BRANCH"
        echo "🎯 目标分支: $protected_branch"
        echo ""
        
        # 切换到新分支来创建 PR
        echo "🔄 切换到源分支进行 PR 创建..."
        echo "   执行命令: git checkout \"$NEW_BRANCH\""
        git checkout "$NEW_BRANCH" 2>/dev/null
        echo "✅ 已切换到 $NEW_BRANCH"
        
        echo ""
        echo "🌐 正在打开浏览器创建 PR..."
        echo "   命令: gh pr create --web --base $protected_branch"
        echo "   执行命令: gh pr create --web --base \"$protected_branch\""
        
        # 使用 --web 打开浏览器，base 指定目标分支
        if gh pr create --web --base "$protected_branch" 2>/dev/null; then
            echo "✅ 已在浏览器中打开 PR 创建页面"
            echo "   请在浏览器中完成 PR 的标题、描述等信息填写"
        else
            echo "⚠️  无法自动打开 PR 页面"
            echo "💡 请手动执行: gh pr create --web --base $protected_branch"
            echo "💡 或访问 GitHub 网页手动创建 PR"
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
        echo ""
        echo "💡 如需绕过 PR 流程直接推送到 $protected_branch："
        echo "   git checkout $protected_branch"
        echo "   git push --no-verify"
        echo "   ⚠️  注意：这将绕过所有保护机制，请谨慎使用！"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # 阻止原始 push 操作
        exit 1
    fi
    
    # 非受保护分支：检查是否包含dev分支的merge
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌿 当前分支: $CURRENT_BRANCH (功能分支)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔍 正在检查功能分支的推送内容..."
    
    # 检查是否有未推送的提交
    local unpushed_commits=0
    echo "📋 正在检查未推送的提交..."
    if git rev-parse @{u} > /dev/null 2>&1; then
        echo "   有远程跟踪分支，正在比较..."
        unpushed_commits=$(git rev-list @{u}..HEAD --count 2>/dev/null || echo "0")
    else
        echo "   没有远程跟踪分支，检查本地提交..."
        unpushed_commits=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    fi
    
    echo "📊 未推送提交数: $unpushed_commits"
    
    # 如果有未推送的提交，检查是否包含dev分支的merge（双重保险）
    if [ "$unpushed_commits" -gt 0 ] && is_merge_operation "$unpushed_commits" && is_merge_from_dev; then
        echo ""
        echo "🚫 错误：检测到从 dev 分支的 merge 操作！"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  dev 分支是开发分支，禁止将其代码 merge 到任何其他分支"
        echo "⚠️  注意：正常情况下 pre-merge-commit 钩子应该已经阻止了这个操作"
        echo ""
        echo "💡 正确的工作流程："
        echo "   1. 从目标分支（如 main）创建功能分支: git checkout main && git checkout -b feature/xxx"
        echo "   2. 在功能分支上开发并提交"
        echo "   3. 推送功能分支: git push origin feature/xxx"
        echo "   4. 创建 PR: feature/xxx → main"
        echo ""
        echo "💡 如需强制绕过此限制："
        echo "   git push --no-verify"
        echo "   ⚠️  注意：这将绕过所有保护机制，强烈不推荐！"
        echo ""
        echo "🔄 如需撤销此次 merge："
        echo "   git reset --hard HEAD~1"
        echo ""
        echo "❌ 拒绝推送包含 dev 分支代码的 merge"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 1
    fi
    
    echo ""
    echo "✅ 功能分支检查通过！"
    echo "🚀 允许推送到功能分支: $CURRENT_BRANCH"
    echo ""
    echo "💡 推送完成后的建议操作："
    echo "   1. 推送完成后，创建 PR 合并到主分支"
    echo "   2. 使用命令: gh pr create --web"
    echo "   3. 或访问 GitHub 网页手动创建 PR"
    echo ""
    echo "💡 如需绕过 PR 流程直接推送到主分支："
    echo "   git checkout main"
    echo "   git merge $CURRENT_BRANCH"
    echo "   git push --no-verify"
    echo "   ⚠️  注意：这将绕过所有保护机制，请谨慎使用！"
    echo ""
    echo "📋 推送即将开始..."
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
echo "   ✓ ✅ 允许 merge 到 main 分支（PR 合并，包括 squash merge）"
echo "   ✓ 🚫 禁止在 main 分支直接 push"
echo "   ✓ 🚫 严格禁止从名为 'dev' 的分支 merge 到任何其他分支（多重钩子保护）"
echo "   ✓ 🆕 自动创建临时分支 feat/premerge-sourcebranch-user-timestamp"
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
echo "      • 在 dev 分支上正常开发和推送"
echo ""
echo "   🚫 禁止的操作："
echo "      • git checkout main && git commit && git push"
echo "        → 直接修改：提示使用 --no-verify 强制推送"
echo "        → merge修改：自动转移到临时分支并创建 PR"
echo "      • git checkout main && git merge dev"
echo "        → ❌ 被 post-merge 钩子检测并自动撤销"
echo "      • git checkout main && git merge --squash dev"
echo "        → ❌ 被 pre-commit 钩子检测并阻止提交"
echo "      • git checkout feature-branch && git merge dev"
echo "        → ❌ 被 post-merge 钩子检测并自动撤销"
echo ""
echo "   🔄 自动流程（仅限merge提交，包括squash merge）："
echo "      1. 在 main 上执行 git push（包含merge提交或squash merge提交）"
echo "      2. 自动创建 feat/premerge-sourcebranch-user-YYYYMMDD_HHMMSS"
echo "      3. 将本地新提交转移到临时分支"
echo "      4. 推送临时分支到远程"
echo "      5. 切回 main 分支（保持原状态）"
echo "      6. 打开浏览器创建 PR"
echo ""
echo "💡 注意事项："
echo "   • PR 功能需要 GitHub CLI: https://github.com/cli/cli"
echo "   • 首次使用需执行: gh auth login"
echo "   • 如需绕过（不推荐）: git push --no-verify"
echo "   • ⚠️  名为 'dev' 的分支严格禁止 merge 到其他分支（在 merge 前就会被阻止）"
echo "   • 从 dev 分支创建功能分支时，应从目标分支（如 main）创建"
echo "   • 新增：多重dev分支保护（pre-commit检测squash + post-merge检测merge）"
echo "   • 新增：详细的执行日志，清晰显示每个步骤的进度和状态"
echo ""
echo "🌿 智能分支命名："
echo "   • 普通 merge: feat/premerge-sourcebranch-user-timestamp"
echo "   • Squash merge: 从 reflog 自动检测原始分支名"
echo "   • 无法检测时: feat/premerge-user-timestamp"
echo ""
echo "🪟 Windows 用户特别提示："
echo "   • 如遇到 'credential-manager-core' 错误，脚本会自动修复"
echo "   • 或手动执行: git config --global credential.helper manager"
echo "   • 建议使用最新版本的 Git for Windows"
echo ""
echo "🔧 快速安装 GitHub CLI："
echo "   macOS:   brew install gh"
echo "   Linux:   sudo apt install gh"
echo "   Windows: winget install --id GitHub.cli"
echo ""
echo "—— Git Hooks 初始化完成 ✅"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔍 调试信息（用于排查 Windows 兼容性问题）："
echo "   系统: $(uname -s 2>/dev/null || echo 'Unknown')"
echo "   Shell: ${SHELL:-Unknown}"
echo "   Git版本: $(git --version)"
echo "   Bash版本: ${BASH_VERSION:-Unknown}"
echo ""
