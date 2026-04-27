# 灰灰网络装机入口（installer）

公开仓 · 仅含 `install.sh` 作为员工装机入口。

## 员工跑

```bash
curl -fsSL https://raw.githubusercontent.com/huihui-network/installer/main/install.sh | bash
```

## 架构

- 本仓 `huihui-network/installer`（**public**）：仅装机入口脚本
- 工作流仓 `huihui-network/claude-shared-config`（**private**）：skill / hooks / agents / 模板（公司 IP）
- 员工跑 install.sh · 在 step 8 走 `gh auth login` + `gh repo clone` 拉私有仓

## v 版本

跟随 `claude-shared-config` v2.0 · v3.0 等。
