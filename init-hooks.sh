#!/bin/bash
# ==========================================
# 🧩 Git Hooks 一键初始化脚本
# 适用于已存在的 Git 仓库
# 执行一次即可永久自动启用 .githooks
# 包含 main 分支合并保护机制
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

# 创建 prepare-commit-msg 钩子（在编辑器打开前阻止 merge）
cat << 'EOF' > "$CUSTOM_HOOKS/prepare-commit-msg"
#!/bin/bash
# ==========================================
# 🛡️ 在 commit 消息准备阶段阻止 merge
# ==========================================

COMMIT_MSG_FILE=$1
COMMIT_SOURCE=$2

# 定义受保护的分支列表（可自定义）
PROTECTED_BRANCHES=("main" "master" "production" "release")

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 检查当前分支是否在保护列表中
is_protected=false
for branch in "${PROTECTED_BRANCHES[@]}"; do
    if [ "$CURRENT_BRANCH" = "$branch" ]; then
        is_protected=true
        break
    fi
done

# 如果是受保护分支且正在执行 merge 操作
if [ "$is_protected" = true ] && [ "$COMMIT_SOURCE" = "merge" ]; then
    echo ""
    echo "=========================================="
    echo "❌ 禁止直接 merge 到 $CURRENT_BRANCH 分支！"
    echo "=========================================="
    echo ""
    echo "🛡️ 受保护分支: ${PROTECTED_BRANCHES[*]}"
    echo ""
    echo "📋 正确流程："
    echo "   1. 推送功能分支到远程仓库"
    echo "   2. 创建 Pull Request"
    echo "   3. 代码审查通过后合并"
    echo ""
    echo "💡 如需临时绕过（不推荐）："
    echo "   git merge --no-verify <branch>"
    echo ""
    
    # 清理 merge 状态
    git merge --abort 2>/dev/null || true
    exit 1
fi

exit 0
EOF

chmod +x "$CUSTOM_HOOKS/prepare-commit-msg"

# 创建 pre-commit 钩子（双重保险）
cat << 'EOF' > "$CUSTOM_HOOKS/pre-commit"
#!/bin/bash
# ==========================================
# 🛡️ commit 阶段再次检查（双重保险）
# ==========================================

# 定义受保护的分支列表（可自定义）
PROTECTED_BRANCHES=("main" "master" "production" "release")

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 检查当前分支是否在保护列表中
is_protected=false
for branch in "${PROTECTED_BRANCHES[@]}"; do
    if [ "$CURRENT_BRANCH" = "$branch" ]; then
        is_protected=true
        break
    fi
done

# 如果是受保护分支且正在执行 merge 操作
if [ "$is_protected" = true ] && [ -f .git/MERGE_HEAD ]; then
    echo ""
    echo "=========================================="
    echo "❌ 禁止直接 merge 到 $CURRENT_BRANCH 分支！"
    echo "=========================================="
    echo ""
    
    # 清理 merge 状态
    git merge --abort 2>/dev/null || true
    exit 1
fi

exit 0
EOF

chmod +x "$CUSTOM_HOOKS/pre-commit"

# 创建 post-merge 钩子（阻止 fast-forward merge）
cat << 'EOF' > "$CUSTOM_HOOKS/post-merge"
#!/bin/bash
# ==========================================
# 🛡️ 检测并回滚 fast-forward merge
# ==========================================

# 定义受保护的分支列表（可自定义）
PROTECTED_BRANCHES=("main" "master" "production" "release")

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 检查当前分支是否在保护列表中
is_protected=false
for branch in "${PROTECTED_BRANCHES[@]}"; do
    if [ "$CURRENT_BRANCH" = "$branch" ]; then
        is_protected=true
        break
    fi
done

# 如果是受保护分支
if [ "$is_protected" = true ]; then
    # 检查是否是 fast-forward merge（通过检查 ORIG_HEAD）
    if [ -n "$GIT_REFLOG_ACTION" ] && echo "$GIT_REFLOG_ACTION" | grep -q "merge"; then
        # 获取 merge 前的 commit
        ORIG_HEAD=$(git rev-parse ORIG_HEAD 2>/dev/null)
        CURRENT_HEAD=$(git rev-parse HEAD)
        
        # 如果 HEAD 改变了，说明发生了 merge
        if [ "$ORIG_HEAD" != "$CURRENT_HEAD" ]; then
            # 检查是否是 fast-forward（没有 merge commit）
            if ! git rev-parse MERGE_HEAD >/dev/null 2>&1; then
                echo ""
                echo "=========================================="
                echo "❌ 检测到 fast-forward merge，已自动回滚！"
                echo "=========================================="
                echo ""
                echo "🛡️ 受保护分支: ${PROTECTED_BRANCHES[*]}"
                echo ""
                echo "📋 正确流程："
                echo "   1. 推送功能分支到远程仓库"
                echo "   2. 创建 Pull Request"
                echo "   3. 代码审查通过后合并"
                echo ""
                
                # 回滚到 merge 前的状态
                git reset --hard ORIG_HEAD
                exit 1
            fi
        fi
    fi
fi

# 保持 hooks 配置（原有功能）
ROOT_DIR=$(git rev-parse --show-toplevel)
git config core.hooksPath "$ROOT_DIR/.githooks" >/dev/null 2>&1
chmod +x "$ROOT_DIR/.githooks/"* 2>/dev/null

exit 0
EOF

chmod +x "$CUSTOM_HOOKS/post-merge"


echo "🛡️ 已创建分支保护钩子："
echo "   - $CUSTOM_HOOKS/prepare-commit-msg (编辑器前阻止)"
echo "   - $CUSTOM_HOOKS/pre-commit (commit 时阻止)"
echo "   - $CUSTOM_HOOKS/post-merge (fast-forward 回滚)"
echo "   - 保护分支: main, master, production, release"
echo "   - 允许在保护分支直接提交"
echo ""

# 为所有自定义 hooks 授权
chmod +x "$CUSTOM_HOOKS"/* 2>/dev/null || true

# 验证配置
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
CURRENT_PATH=$(git config core.hooksPath)
if [ "$CURRENT_PATH" == "$CUSTOM_HOOKS" ]; then
    echo "🎉 核心配置验证通过"
    echo "   core.hooksPath = $CURRENT_PATH"
else
    echo "⚠️ 未成功设置 core.hooksPath，请检查 Git 配置"
fi

echo ""
echo "✨ 初始化完成！已启用以下功能："
echo "   ✓ 自定义 hooks 目录管理"
echo "   ✓ 切换分支/合并后自动恢复配置"
echo "   ✓ 三重保护阻止任何形式的 merge"
echo "   ✓ 允许在保护分支直接提交（适用于紧急修复）"
echo "   ✓ 提交消息格式检查"
echo ""
echo "📌 注意事项："
echo "   • 本地 hooks 可通过 --no-verify 绕过"
echo "   • 生产环境建议配置服务器端保护规则"
echo "   • 团队成员需要执行此脚本以启用保护"
echo ""
echo "—— Git Hooks 初始化完成 ✅"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
