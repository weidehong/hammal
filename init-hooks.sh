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
# 1.5. pre-merge-commit：阻止从dev分支的merge
# ==========================================

cat << 'EOF' > "$CUSTOM_HOOKS/pre-merge-commit"
#!/bin/bash
# ==========================================
# 🚫 pre-merge-commit Hook - 禁止从dev分支merge
# 在merge提交创建前检测并阻止从dev分支的merge操作
# ==========================================

# 检查是否正在进行merge操作
if [ ! -f ".git/MERGE_HEAD" ]; then
    # 不是merge操作，允许通过
    exit 0
fi

# 获取正在merge的分支信息
MERGE_HEAD=$(cat .git/MERGE_HEAD 2>/dev/null)
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 尝试获取merge的源分支名
MERGE_BRANCH=""

# 方法1: 从MERGE_MSG获取分支名
if [ -f ".git/MERGE_MSG" ]; then
    MERGE_MSG=$(cat .git/MERGE_MSG 2>/dev/null)
    # 提取分支名，支持多种格式
    if echo "$MERGE_MSG" | grep -q "Merge branch"; then
        MERGE_BRANCH=$(echo "$MERGE_MSG" | sed -n "s/.*Merge branch '\([^']*\)'.*/\1/p" | head -1)
    elif echo "$MERGE_MSG" | grep -q "Merge remote-tracking branch"; then
        MERGE_BRANCH=$(echo "$MERGE_MSG" | sed -n "s/.*Merge remote-tracking branch '\([^']*\)'.*/\1/p" | head -1)
    fi
fi

# 方法2: 从reflog获取分支名
if [ -z "$MERGE_BRANCH" ]; then
    MERGE_BRANCH=$(git reflog -1 --pretty=format:"%gs" 2>/dev/null | sed -n "s/.*merge \([^:]*\).*/\1/p")
fi

# 方法3: 检查MERGE_HEAD对应的分支
if [ -z "$MERGE_BRANCH" ] && [ -n "$MERGE_HEAD" ]; then
    # 尝试找到包含这个commit的远程分支
    POSSIBLE_BRANCHES=$(git branch -r --contains "$MERGE_HEAD" 2>/dev/null | grep -v HEAD | sed 's/^[[:space:]]*//' | sed 's/origin\///')
    for branch in $POSSIBLE_BRANCHES; do
        if echo "$branch" | grep -q "dev"; then
            MERGE_BRANCH="$branch"
            break
        fi
    done
fi

# 检查是否是从dev分支的merge
if [ -n "$MERGE_BRANCH" ] && echo "$MERGE_BRANCH" | grep -q "dev"; then
    echo ""
    echo "🚫 错误：禁止从 dev 分支进行 merge 操作！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  检测到正在从 '$MERGE_BRANCH' 分支 merge 到 '$CURRENT_BRANCH'"
    echo "⚠️  dev 分支是开发分支，禁止将其代码 merge 到其他分支"
    echo ""
    echo "💡 正确的工作流程："
    echo "   1. 取消当前merge: git merge --abort"
    echo "   2. 从目标分支创建功能分支: git checkout -b feature/xxx"
    echo "   3. 在功能分支上开发并提交"
    echo "   4. 推送功能分支: git push origin feature/xxx"
    echo "   5. 创建 PR: feature/xxx → $CURRENT_BRANCH"
    echo ""
    echo "🔄 立即取消merge："
    echo "   git merge --abort"
    echo ""
    echo "❌ 阻止创建 merge 提交"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

# 如果无法确定merge源分支，给出警告但允许通过
if [ -z "$MERGE_BRANCH" ]; then
    echo ""
    echo "⚠️  警告：无法确定 merge 源分支"
    echo "💡 如果你正在从 dev 分支 merge，请手动取消："
    echo "   git merge --abort"
    echo ""
fi

exit 0
EOF

chmod +x "$CUSTOM_HOOKS/pre-merge-commit"

echo "🚫 已创建 pre-merge-commit 钩子（阻止从dev分支merge）"
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

# 检查并修复 Windows Git 凭据管理器问题
check_windows_git_credentials() {
    if [ "$OS_TYPE" = "windows" ]; then
        # 检查是否配置了已弃用的 credential-manager-core
        local credential_helper=$(git config --global credential.helper 2>/dev/null)
        if [ "$credential_helper" = "manager-core" ]; then
            echo ""
            echo "⚠️  检测到 Windows Git 凭据管理器配置问题"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "🔧 正在修复 credential-manager-core 配置..."
            
            # 尝试修复配置
            if git config --global credential.helper manager 2>/dev/null; then
                echo "✅ 已将 credential.helper 从 'manager-core' 更新为 'manager'"
            else
                echo "⚠️  无法自动修复，请手动执行以下命令："
                echo "   git config --global credential.helper manager"
            fi
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo ""
        fi
        
        # 检查 Git Credential Manager 是否可用
        if ! command -v git-credential-manager >/dev/null 2>&1; then
            echo ""
            echo "💡 Windows Git 凭据管理器提示："
            echo "   如果遇到 'credential-manager-core' 错误，请："
            echo "   1. 更新到最新版本的 Git for Windows"
            echo "   2. 或执行: git config --global credential.helper manager"
            echo "   3. 或安装最新的 Git Credential Manager"
            echo ""
        fi
    fi
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
    
    # 获取当前main分支下合并进来的所有分支（排除premerge分支和main/master分支）
    local merged_branches=""
    merged_branches=$(git branch --merged | grep -iv "premerge" | grep -iv "main\|master" | \
        sed 's/^[* ]*//' | \
        tr '\n' '-' | \
        sed 's/-$//' | \
        tr '/' '-' | \
        cut -c1-30)
    
    # 如果没有找到合并的分支，使用简单格式
    if [ -z "$merged_branches" ]; then
        echo "feat/premerge-${user_name}-${timestamp}"
    else
        # 清理分支名，确保符合 Git 分支命名规范
        merged_branches=$(echo "$merged_branches" | sed 's/[^a-zA-Z0-9_-]//g')
        echo "feat/premerge-${merged_branches}-${user_name}-${timestamp}"
    fi
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
            if echo "$recent_merge_msg" | grep -q "merge.*dev\|merge.*origin/dev"; then
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
            if echo "$commit_msg" | grep -q "dev\|origin/dev"; then
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
        if echo "$recent_commits" | grep -qi "dev\|origin/dev\|from.*dev\|merge.*dev"; then
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
                
                if echo "$all_commit_msgs" | grep -qi "dev"; then
                    return 0
                fi
            fi
        fi
    fi
    
    return 1
}


# ========== 主逻辑 ==========
main() {
    # Windows 系统检查并修复凭据管理器问题
    check_windows_git_credentials
    
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
        
        # 检查是否是merge操作（包括fast-forward merge和squash merge）
        if is_merge_operation "$UNPUSHED_COMMITS"; then
            echo "🔀 检测到merge操作，这可能是从其他分支合并的更改（包括 squash merge）"
            
            # 检查是否是从dev分支的merge
            if is_merge_from_dev; then
                echo ""
                echo "🚫 错误：检测到从 dev 分支的 merge 操作！"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "⚠️  dev 分支是开发分支，禁止将其代码 merge 到其他分支"
                echo ""
                echo "💡 正确的工作流程："
                echo "   1. 从 $CURRENT_BRANCH 创建功能分支: git checkout -b feature/xxx"
                echo "   2. 在功能分支上开发并提交"
                echo "   3. 推送功能分支: git push origin feature/xxx"
                echo "   4. 创建 PR: feature/xxx → $CURRENT_BRANCH"
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
    
    # 非受保护分支：检查是否包含dev分支的merge
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🌿 当前分支: $CURRENT_BRANCH"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 检查是否有未推送的提交
    local unpushed_commits=0
    if git rev-parse @{u} > /dev/null 2>&1; then
        unpushed_commits=$(git rev-list @{u}..HEAD --count 2>/dev/null || echo "0")
    else
        unpushed_commits=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    fi
    
    # 如果有未推送的提交，检查是否包含dev分支的merge
    if [ "$unpushed_commits" -gt 0 ] && is_merge_operation "$unpushed_commits" && is_merge_from_dev; then
        echo ""
        echo "🚫 错误：检测到从 dev 分支的 merge 操作！"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "⚠️  dev 分支是开发分支，禁止将其代码 merge 到任何其他分支"
        echo ""
        echo "💡 正确的工作流程："
        echo "   1. 从目标分支（如 main）创建功能分支: git checkout main && git checkout -b feature/xxx"
        echo "   2. 在功能分支上开发并提交"
        echo "   3. 推送功能分支: git push origin feature/xxx"
        echo "   4. 创建 PR: feature/xxx → main"
        echo ""
        echo "🔄 如需撤销此次 merge："
        echo "   git reset --hard HEAD~1"
        echo ""
        echo "❌ 拒绝推送包含 dev 分支代码的 merge"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        exit 1
    fi
    
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
echo "   ✓ ✅ 允许 merge 到 main 分支（PR 合并，包括 squash merge）"
echo "   ✓ 🚫 禁止在 main 分支直接 push"
echo "   ✓ 🚫 禁止从 dev 分支 merge 到任何其他分支（包括 squash merge）"
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
echo "      • 在 dev 分支上正常开发和推送"
echo ""
echo "   🚫 禁止的操作："
echo "      • git checkout main && git commit && git push"
echo "        → 直接修改：提示使用 --no-verify 强制推送"
echo "        → merge修改：自动转移到临时分支并创建 PR"
echo "      • git checkout main && git merge dev"
echo "        → 禁止从 dev 分支 merge 到任何其他分支"
echo "      • git checkout main && git merge --squash dev"
echo "        → 禁止从 dev 分支 squash merge 到任何其他分支"
echo "      • git checkout feature-branch && git merge dev"
echo "        → 禁止从 dev 分支 merge 到任何其他分支"
echo ""
echo "   🔄 自动流程（仅限merge提交，包括squash merge）："
echo "      1. 在 main 上执行 git push（包含merge提交或squash merge提交）"
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
echo "   • dev 分支仅用于开发，禁止 merge 到其他分支"
echo "   • 从 dev 分支创建功能分支时，应从目标分支（如 main）创建"
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
