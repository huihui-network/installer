#!/bin/bash
# 灰灰网络公司一键装机脚本 v1
# 用法：curl -fsSL https://install.hhwl.xyz/v1.sh | bash
#
# 设计：12 步 · 幂等 · 错误日志 · 失败可重跑

set -euo pipefail
LOG="/tmp/hhwl-install-$(date +%s).log"
exec > >(tee "$LOG") 2>&1

INSTALL_VERSION="v1.0"
SHARED_REPO="huihui-network/claude-shared-config"
DMG_URL="https://github.com/huihui-network/codechat-boss-build/releases/latest/download/CodeChat-Boss.dmg"
BACKEND_BASE="https://chat.hhwl.xyz"
# 装机自身的 raw URL（域名 install.hhwl.xyz 上线前 fallback）
INSTALL_RAW_URL="https://raw.githubusercontent.com/$SHARED_REPO/main/install.sh"

# ============= 工具函数 =============
ok() { echo "✅ $*"; }
warn() { echo "⚠️  $*"; }
err() { echo "❌ $*" >&2; exit 1; }
# 从 /dev/tty 读 · curl|bash 模式下 stdin 是脚本流 · 必走 tty
ask() { local VAL; read -p "$1 [$2]: " VAL < /dev/tty; echo "${VAL:-$2}"; }
# sed 转义：用户输入含 | & / 等 sed metachar 时安全替换
sed_escape() { printf '%s' "$1" | sed -e 's/[\&|/]/\\&/g'; }

# ============= 前置检查 =============
echo "==========================================="
echo "  灰灰网络公司装机 · $INSTALL_VERSION"
echo "  日志：$LOG"
echo "==========================================="

# macOS 14+
if [[ "$(uname)" != "Darwin" ]]; then err "仅支持 macOS"; fi
MAC_VER=$(sw_vers -productVersion | cut -d. -f1)
[[ "$MAC_VER" -ge 14 ]] || err "macOS 14+ required (当前 $MAC_VER)"
ok "macOS $MAC_VER"

# 磁盘 5GB
DISK_FREE=$(df -g ~ | awk 'NR==2 {print $4}')
[[ "$DISK_FREE" -ge 5 ]] || err "磁盘空间不足 5GB（当前 ${DISK_FREE}GB）"
ok "磁盘 ${DISK_FREE}GB 可用"

# 网络（中国网络 apple.com 慢 · 用 HEAD only + 多端点 fallback）
NET_OK=0
for endpoint in "$BACKEND_BASE" "https://www.baidu.com" "https://github.com"; do
  if curl -fsI --max-time 10 "$endpoint" >/dev/null 2>&1; then
    NET_OK=1; break
  fi
done
[[ "$NET_OK" -eq 1 ]] || err "网络不通（chat.hhwl.xyz / baidu / github 都不通）"
ok "网络通"

# ============= trap + step marker（半失败可重跑）=============
STATE_FILE="$HOME/.claude/.install_state"
mkdir -p "$HOME/.claude"
trap 'EXIT_CODE=$?; if [[ $EXIT_CODE -ne 0 ]]; then echo "❌ install.sh 失败 · 已记录到 $STATE_FILE · 重跑 install.sh 自动跳过已完成步骤"; fi' EXIT
mark_step() { echo "$1" > "$STATE_FILE"; }
RESUME_FROM=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
[[ "$RESUME_FROM" -gt "0" ]] && warn "上次完成到 step $RESUME_FROM · 自动跳过已完成"

# Xcode CLT（brew 前置）
if ! xcode-select -p >/dev/null 2>&1; then
  warn "Xcode Command Line Tools 未装 · 启动安装（弹窗 + 5-15 min）"
  xcode-select --install 2>/dev/null || true
  echo ""
  echo "请在弹出的 GUI 完成安装 · 完成后按回车继续..."
  read -r
  xcode-select -p >/dev/null 2>&1 || err "Xcode CLT 装失败"
fi
ok "Xcode CLT 已装"

# ============= Step 1 · Homebrew =============
if ! command -v brew &>/dev/null; then
  echo "▶ Step 1 · 装 Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # M / Intel 路径自适应
  [[ -d /opt/homebrew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
  [[ -d /usr/local/Homebrew ]] && eval "$(/usr/local/bin/brew shellenv)"
fi
ok "Step 1 · Homebrew $(brew --version | head -1)"
mark_step 1

# ============= Step 2 · Node.js LTS ≥20 =============
if ! command -v node &>/dev/null || [[ "$(node -v | cut -dv -f2 | cut -d. -f1)" -lt 20 ]]; then
  echo "▶ Step 2 · 装 Node.js LTS"
  brew install node
fi
ok "Step 2 · Node $(node -v)"
mark_step 2

# ============= Step 3 · CLI 工具链 =============
echo "▶ Step 3 · 装 CLI 工具链"
for tool in git jq gh awscli yq tree; do
  if ! command -v $tool &>/dev/null; then
    brew install $tool
  fi
done
ok "Step 3 · git/jq/gh/awscli/yq/tree 齐"
mark_step 3

# ============= Step 4 · Claude CLI =============
if ! command -v claude &>/dev/null; then
  echo "▶ Step 4 · 装 Claude CLI"
  npm install -g @anthropic-ai/claude-code
fi
ok "Step 4 · Claude $(claude --version 2>/dev/null || echo 'installed')"
mark_step 4

# ============= Step 5 · 2 Q 引导（员工是 boss · 不是 PM/DEV）=============
echo ""
echo "▶ Step 5 · 配置引导"
echo "  💡 你是项目 boss · Claude Code 是你的工具 · 后续你自己造 PM/DEV Code 实例"
echo ""

PROJECT=$(ask "项目名（你自己取 · 如 my-app / website-redesign）" "我的项目")
PROJECT_DIR="$HOME/Desktop/$PROJECT"
TASK_DIR="$PROJECT_DIR/.claude-tasks"

ok "Step 5 · 项目=$PROJECT"
mark_step 5

# ============= Step 6 · 强改密码（先于 token 拿）=============
echo ""
echo "▶ Step 6 · CodeChat 账号激活（老板已建好 user · 你需改默认密码）"
USERNAME=$(ask "你的 CodeChat 用户名" "")
[[ -n "$USERNAME" ]] || err "用户名不能为空"

INITIAL_PASSWORD=$(ask "初始密码（老板私发 · 默认 test1234）" "test1234")
echo "请输入新密码（至少 8 位）："
# read -s 必走 /dev/tty · 否则 curl|bash 模式下 stdin 是脚本流 · 读到空
read -s NEW_PASSWORD < /dev/tty
echo  # 换行
[[ ${#NEW_PASSWORD} -ge 8 ]] || err "密码至少 8 位"

# 后端真实 schema（验证过 chat.hhwl.xyz/openapi.json）：
# - POST /api/users/login: body={name, password} → returns {id, mcp_token, ...}
# - PUT /api/users/profile: body={old_password, new_password} · 用 X-Token header
# - 后端 auth 全部 X-Token 头（不是 Authorization Bearer）

# Step 6.1 · 用初始密码 login 拿临时 token
LOGIN_BODY_INIT=$(jq -n --arg n "$USERNAME" --arg p "$INITIAL_PASSWORD" '{name:$n, password:$p}')
echo "  → 调 /api/users/login（用初始密码 · 拿 token 改密）"
LOGIN_RESP_INIT=$(curl -sf --max-time 30 -X POST "$BACKEND_BASE/api/users/login" \
  -H "Content-Type: application/json" -d "$LOGIN_BODY_INIT" 2>/dev/null || echo "")

# 幂等性：初始密码失败可能因为已改过 · 试新密码兜底
if [[ -z "$LOGIN_RESP_INIT" ]] || [[ "$(echo "$LOGIN_RESP_INIT" | jq -r '.mcp_token // empty')" == "" ]]; then
  warn "  初始密码登录失败 · 试新密码（如已改过）"
  LOGIN_BODY_NEW=$(jq -n --arg n "$USERNAME" --arg p "$NEW_PASSWORD" '{name:$n, password:$p}')
  LOGIN_RESP=$(curl -sf --max-time 30 -X POST "$BACKEND_BASE/api/users/login" \
    -H "Content-Type: application/json" -d "$LOGIN_BODY_NEW" \
    || err "login 失败 · 检查用户名/密码 · 或老板未建 user")
else
  TEMP_TOKEN=$(echo "$LOGIN_RESP_INIT" | jq -r '.mcp_token')
  [[ -n "$TEMP_TOKEN" && "$TEMP_TOKEN" != "null" ]] || err "初始 token 拿不到"

  # Step 6.2 · 用临时 token 改密码（PUT /api/users/profile · X-Token header）
  CHANGE_BODY_PROFILE=$(jq -n --arg op "$INITIAL_PASSWORD" --arg np "$NEW_PASSWORD" \
    '{old_password:$op, new_password:$np}')
  echo "  → 调 PUT /api/users/profile（改密）"
  curl -sf --max-time 30 -X PUT "$BACKEND_BASE/api/users/profile" \
    -H "X-Token: $TEMP_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CHANGE_BODY_PROFILE" >/dev/null \
    || err "改密失败 · 检查初始密码是否正确"

  # Step 6.3 · 用新密码 login 拿正式 token（rotation · 旧 token 自动失效）
  LOGIN_BODY_NEW=$(jq -n --arg n "$USERNAME" --arg p "$NEW_PASSWORD" '{name:$n, password:$p}')
  echo "  → 调 /api/users/login（新密码 · token rotation）"
  LOGIN_RESP=$(curl -sf --max-time 30 -X POST "$BACKEND_BASE/api/users/login" \
    -H "Content-Type: application/json" -d "$LOGIN_BODY_NEW" \
    || err "改密后 login 失败")
fi

MCP_TOKEN=$(echo "$LOGIN_RESP" | jq -r '.mcp_token')
USER_ID=$(echo "$LOGIN_RESP" | jq -r '.id')
[[ -n "$MCP_TOKEN" && "$MCP_TOKEN" != "null" ]] || err "拿 mcp_token 失败"
[[ -n "$USER_ID" && "$USER_ID" != "null" ]] || err "拿 user_id 失败"

ok "Step 6 · mcp_token + id 拿到（已改密 + 新 token rotation）"
mark_step 6

# ============= Step 7 · CodeChat App =============
echo "▶ Step 7 · 装 CodeChat Boss App"
DMG_PATH="/tmp/CodeChat-Boss.dmg"
if [[ ! -d "/Applications/CodeChat Boss.app" ]]; then
  curl -fsSL --max-time 120 "$DMG_URL" -o "$DMG_PATH"
  # 动态拿挂载点（不假设卷标名）
  MOUNT_OUT=$(hdiutil attach "$DMG_PATH" -nobrowse)
  MOUNT_PATH=$(echo "$MOUNT_OUT" | tail -1 | awk -F'\t' '{print $NF}')
  [[ -d "$MOUNT_PATH" ]] || err "DMG 挂载失败 · path=$MOUNT_PATH"

  APP_SRC=$(find "$MOUNT_PATH" -maxdepth 2 -name "*.app" -type d | head -1)
  [[ -d "$APP_SRC" ]] || err "DMG 中无 .app 文件"

  cp -R "$APP_SRC" /Applications/ || err "/Applications 写权限不足 · 需 admin"
  hdiutil detach "$MOUNT_PATH" -quiet
  xattr -cr "/Applications/CodeChat Boss.app" 2>/dev/null || true
  rm -f "$DMG_PATH"
fi
ok "Step 7 · CodeChat Boss.app 装好"
mark_step 7

# ============= Step 8 · gh auth + claude-shared-config =============
echo "▶ Step 8 · 拉中央仓 claude-shared-config"
if ! gh auth status &>/dev/null; then
  warn "gh 未登录 · 请按提示完成 GitHub 授权"
  gh auth login --web
fi

CSCW="$HOME/.claude-shared-config"
if [[ -d "$CSCW/.git" ]]; then
  # 已是 git repo · 拉新版
  cd "$CSCW" && git pull
elif [[ -d "$CSCW" ]]; then
  # 目录存在但不是 git repo · 备份 + 重 clone
  warn "  $CSCW 已存在但非 git repo · 备份 → 重 clone"
  mv "$CSCW" "$CSCW.bak-$(date +%s)"
  gh repo clone "$SHARED_REPO" "$CSCW"
else
  # 首次 clone
  gh repo clone "$SHARED_REPO" "$CSCW"
fi
cd "$CSCW" && bash deploy.sh
ok "Step 8 · 中央仓部署完"
mark_step 8

# ============= Step 9 · 模板 sed 替换 =============
echo "▶ Step 9 · 写项目目录（员工是 boss）"
mkdir -p "$PROJECT_DIR" "$TASK_DIR"
mkdir -p "$PROJECT_DIR/memory" "$PROJECT_DIR/docs"
# .roles/ 留给员工后续造 Code 角色用（员工通过 CodeChat 创建 PM/DEV 时填）
mkdir -p "$PROJECT_DIR/.roles"
mkdir -p "$HOME/.claude/session-data"

# Claude Code projects normalized path
# 算法：把 PROJECT_DIR 里的 / 换成 -（如 /Users/quan/Desktop/X → -Users-quan-Desktop-X）
# Claude CLI 启动后会用此 normalize 算法 · 我们用同样规则
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects/$(echo "$PROJECT_DIR" | sed 's|/|-|g')"
mkdir -p "$CLAUDE_PROJECTS_DIR/memory"

# 兜底：如果 claude CLI 真实 normalize path 不一致 · 通过 claude --print-projects-dir 取
# (当前 claude CLI 没此命令 · 用我们的算法即可 · v1.1 跟踪)

# 转义用户输入变量（防 sed metachar 破坏）
E_PROJECT=$(sed_escape "$PROJECT")
E_PROJECT_DIR=$(sed_escape "$PROJECT_DIR")
E_USERNAME=$(sed_escape "$USERNAME")
E_USER_ID=$(sed_escape "$USER_ID")
E_TASK_DIR=$(sed_escape "$TASK_DIR")
E_CLAUDE_PROJECTS_DIR=$(sed_escape "$CLAUDE_PROJECTS_DIR")
E_HOME=$(sed_escape "$HOME")
E_MACHINE=$(sed_escape "$(hostname -s)")

# sed 函数 · 员工是 boss
# 真实替换：员工自己 + 项目相关
# 空替换：PM/DEV/上级/群 ID（员工后续通过 CodeChat App 造 Code 角色时再填）
sed_template() {
  local SRC="$1" DST="$2"
  sed \
    -e "s|{{PROJECT}}|$E_PROJECT|g" \
    -e "s|{{PROJECT_DIR}}|$E_PROJECT_DIR|g" \
    -e "s|{{MACHINE}}|$E_MACHINE|g" \
    -e "s|{{CODECHAT_NAME}}|$E_USERNAME|g" \
    -e "s|{{USER_ID}}|$E_USER_ID|g" \
    -e "s|{{TASK_DIR}}|$E_TASK_DIR|g" \
    -e "s|{{MEMORY_DIR}}|$E_PROJECT_DIR/memory|g" \
    -e "s|{{CLAUDE_PROJECTS_DIR}}|$E_CLAUDE_PROJECTS_DIR|g" \
    -e "s|{{INSTALL_DATE}}|$(date +%Y-%m-%d)|g" \
    -e "s|{{KEYCHAIN_SERVICE}}|hhwl-mcp|g" \
    -e "s|{{ROLE}}||g" \
    -e "s|{{ROLE_NAME}}||g" \
    -e "s|{{SUPERIOR}}||g" \
    -e "s|{{SUPERIOR_ID}}||g" \
    -e "s|{{SUBORDINATE}}||g" \
    -e "s|{{SUBORDINATE_ID}}||g" \
    -e "s|{{PM_NAME}}||g" \
    -e "s|{{PM_ID}}||g" \
    -e "s|{{BOSS_PRIVATE_CONV}}||g" \
    -e "s|{{BOSS_ID}}||g" \
    -e "s|{{PROJECT_GROUP_ID}}||g" \
    -e "s|{{HQ_GROUP_ID}}||g" \
    -e "s|{{PM_DISPLAY_NAME}}||g" \
    -e "s|{{DEV_DISPLAY_NAME}}||g" \
    -e "s|\$HOME|$E_HOME|g" \
    "$SRC" > "$DST"
}

# 写项目模板（员工是 boss · 不分 PM/DEV）
sed_template "$CSCW/templates/CLAUDE.md.项目根.tpl" "$PROJECT_DIR/CLAUDE.md"
sed_template "$CSCW/templates/启动.command.tpl" "$PROJECT_DIR/启动.command"
sed_template "$CSCW/templates/MEMORY.md.tpl" "$PROJECT_DIR/memory/MEMORY.md"
# CLAUDE.md.PM.tpl / CLAUDE.md.DEV.tpl 留在 ~/.claude/templates/ · 员工以后造 Code 时用

# PRD-template.md 直接 cp · 不 sed（用 <<XXX>> 占位符）
cp "$CSCW/templates/PRD-template.md" "$PROJECT_DIR/docs/"

# 重装保护：备份现有项目根 CLAUDE.md（如已存在）
if [[ -f "$PROJECT_DIR/CLAUDE.md" ]]; then
  cp "$PROJECT_DIR/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md.bak-$(date +%s)"
  warn "  已备份现有 CLAUDE.md → .bak"
fi

# ⚠️ sed 顺序倒装：先在 staged 里 sed → rsync 到 ~/.claude/
# staged 用 mktemp 不污染 git repo · 防 mtime 卡死
STAGE=$(mktemp -d /tmp/hhwl-staged-XXXXXX)
# 链式 trap：保留原失败提示 + 加清 staged
trap "rm -rf '$STAGE'; if [[ \$? -ne 0 ]]; then echo '❌ install.sh 失败 · 重跑自动跳过已完成步骤'; fi" EXIT
mkdir -p "$STAGE/skills"

# 5 个 skill sed → staged
for s in pm-dispatch pm-validate dev-selftest hhwl-brainstorm retrospect; do
  if [[ -f "$CSCW/skills/$s/SKILL.md" ]]; then
    mkdir -p "$STAGE/skills/$s"
    sed_template "$CSCW/skills/$s/SKILL.md" "$STAGE/skills/$s/SKILL.md"
  fi
done

# ONBOARDING.md / GLOSSARY.md sed → staged
for f in ONBOARDING.md GLOSSARY.md; do
  [[ -f "$CSCW/templates/$f" ]] && sed_template "$CSCW/templates/$f" "$STAGE/$f"
done

# rsync staged → ~/.claude/（强制覆盖 · 不依赖 mtime）
rsync -av --safe-links "$STAGE/skills/" "$HOME/.claude/skills/"
[[ -f "$STAGE/ONBOARDING.md" ]] && cp "$STAGE/ONBOARDING.md" "$HOME/.claude/ONBOARDING.md"
[[ -f "$STAGE/GLOSSARY.md" ]] && cp "$STAGE/GLOSSARY.md" "$HOME/.claude/GLOSSARY.md"

# 清 staged
rm -rf "$STAGE"

# hooks.json $HOME 替换（这一步必须在 ~/.claude/ 里做 · 因为 deploy.sh 已 rsync 过）
sed -i.bak "s|\$HOME|$E_HOME|g" "$HOME/.claude/hooks/hooks.json"
rm -f "$HOME/.claude/hooks/hooks.json.bak"

ok "Step 9 · 模板 + skill + ONBOARDING/GLOSSARY 全 sed 替换完（顺序倒装防 mtime 卡）"
mark_step 9

# ============= Step 10 · keychain 写 token =============
echo "▶ Step 10 · 写 mcp_token 到 macOS 钥匙串"
# keychain -T 白名单：claude CLI 实际路径动态拿（防 npm prefix 自定义）
CLAUDE_BIN=$(command -v claude)
[[ -n "$CLAUDE_BIN" ]] || err "claude CLI 找不到 · install.sh step 4 失败？"
APP_BIN="/Applications/CodeChat Boss.app/Contents/MacOS/CodeChat Boss"

security add-generic-password \
  -a "hhwl-mcp" \
  -s "$USER" \
  -w "$MCP_TOKEN" \
  -T "$CLAUDE_BIN" \
  -T "$APP_BIN" \
  -U
ok "Step 10 · keychain 写入 (claude=$CLAUDE_BIN)"
mark_step 10

# ============= Step 11 · 权限 + chmod =============
echo "▶ Step 11 · 设权限"
chmod 755 "$PROJECT_DIR/启动.command"
chmod 700 "$PROJECT_DIR/.roles" 2>/dev/null || true
chmod -R +x "$HOME/.claude/scripts/hooks/"*.js 2>/dev/null || true
chmod +x "$HOME/.claude/hooks/"*.sh 2>/dev/null || true
chmod +x "$HOME/.claude/scripts/pm-validate-screenshot.sh" 2>/dev/null || true
ok "Step 11 · 权限设完"
mark_step 11

# ============= Step 12 · verify =============
echo ""
echo "▶ Step 12 · 12 项 verify"
PASS=0; FAIL=0
# 注意：用 PASS=$((PASS+1)) 而非 ((PASS++))
# 后者在 set -e + bash 3.2 (macOS) 下当 PASS=0 时会触发 exit 1 中断 verify
check() {
  if eval "$2" >/dev/null 2>&1; then echo "  ✅ $1"; PASS=$((PASS+1)); else echo "  ❌ $1"; FAIL=$((FAIL+1)); fi
}
check "claude CLI" "command -v claude"
check "node ≥ 20" "[[ \$(node -v | cut -dv -f2 | cut -d. -f1) -ge 20 ]]"
check "gh logged in" "gh auth status"
check "CodeChat App 装好" "[[ -d '/Applications/CodeChat Boss.app' ]]"
check "项目目录" "[[ -d '$PROJECT_DIR' ]]"
check "启动.command 可执行" "[[ -x '$PROJECT_DIR/启动.command' ]]"
check "keychain 写入" "security find-generic-password -a hhwl-mcp -s \$USER -w >/dev/null"
check "claude-shared-config" "[[ -d '$CSCW' ]]"
check "skill pm-dispatch" "[[ -f \$HOME/.claude/skills/pm-dispatch/SKILL.md ]]"
check "skill hhwl-brainstorm" "[[ -f \$HOME/.claude/skills/hhwl-brainstorm/SKILL.md ]]"
check "hooks 装好" "[[ -d \$HOME/.claude/hooks ]]"
check "session-data 目录" "[[ -d \$HOME/.claude/session-data ]]"
check "hooks.json \$HOME 已替换" "! grep -q '\\\\\\\$HOME' '$HOME/.claude/hooks/hooks.json'"
check "项目 CLAUDE.md 占位符已 sed" "! grep -q '{{[A-Z_]*}}' '$PROJECT_DIR/CLAUDE.md'"
check "skill 5 个全装" "[[ -f '$HOME/.claude/skills/pm-dispatch/SKILL.md' && -f '$HOME/.claude/skills/retrospect/SKILL.md' ]]"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "==========================================="
  echo "🎉 装机完成 · 12 项 ✅ · 用时 $SECONDS 秒"
  echo ""
  echo "下一步："
  echo "  1. 双击 $PROJECT_DIR/启动.command（你直接跟 Claude 对话 · 你是 boss）"
  echo "  2. 打开 CodeChat Boss App（自动登录）"
  echo "  3. 阅读 ~/.claude/ONBOARDING.md（30 min quickstart）"
  echo "  4. 想造 Code-PM/Code-DEV？打开 CodeChat App → '+ 新员工' → 填角色"
  echo "==========================================="

  # 员工是 boss · 装机成功员工自己看终端 · 不发 IM
  mark_step 12
  rm -f "$STATE_FILE"
else
  echo "❌ 装机失败 · $PASS ✅ / $FAIL ❌ · 看日志 $LOG"
  exit 1
fi
