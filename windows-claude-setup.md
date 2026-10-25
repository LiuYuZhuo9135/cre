# Windows 下让 Claude Code 干活像 Linux 的配置

> 目标：在 Windows 上运行 Claude Code，让 AI 调工具、处理中文、编码行为和 Linux 一致。

## 一、让 AI 调工具用 bash（而不是 PowerShell）

先安装 [Git for Windows](https://git-scm.com/)（自带 Git Bash），然后让 Claude Code 把 Git Bash 当主 shell。

在项目（或用户级）的 `.claude/settings.json` 里加：

```json
{
  "env": {
    "CLAUDE_CODE_GIT_BASH_PATH": "C:\\Program Files\\Git\\bin\\bash.exe",
    "CLAUDE_CODE_USE_POWERSHELL_TOOL": "0"
  }
}
```

- `CLAUDE_CODE_GIT_BASH_PATH`：Git Bash 位置（装好 Git 通常能自动找到，此键可省略）。
- `CLAUDE_CODE_USE_POWERSHELL_TOOL=0`：**关键**。Windows 上即使装了 Git Bash，PowerShell 默认仍是主 shell；设成 `0` 才能让 AI 的命令真正走 Git Bash。
- ⚠️ 只有在确认装了 Git Bash 时才设 `0`，否则等于没有 shell 可用。

注意：`defaultShell` 这个设置项只影响你自己敲的 `!` 命令，**不影响** AI 调工具，别用错。

## 二、中文内容：文件本身必须是 UTF-8

Claude Code 的文件工具遇到非 UTF-8（GBK）文件时：

- Edit 直接拒绝（报 `File is not valid UTF-8`）
- Read 把读不出的字节显示成乱码（�）

所以中文问题的根源是**文件编码**，不是终端显示。三步：

1. **把 GBK 文件批量转成 UTF-8**：用本目录的 `gbk2utf8.sh`，或手动 `iconv -f GB18030 -t UTF-8 旧文件 > 新文件`。
2. **系统级**：设置 → 时间和语言 → 语言和区域 → 管理语言设置 → 更改系统区域设置 → 勾选「Beta：使用 Unicode UTF-8 提供全球语言支持」，重启。
3. **终端兜底**：PowerShell 里 `chcp 65001`。

> 说明：第 2、3 步是社区通行做法，官方文档未写死编码配置；系统级 UTF-8 Beta 可能影响老牌中文软件，先测再用。

## 三、换行符与路径

- 换行符统一 LF：`git config --global core.autocrlf input`，或在项目加 `.gitattributes`：

  ```
  * text=auto
  *.py  text eol=lf
  *.sh  text eol=lf
  *.md  text eol=lf
  ```

- 路径统一正斜杠 `/`，避免 `\` 转义问题。

## 四、什么时候需要 WSL2

上面的 Git Bash 方案已覆盖：bash 命令习惯 + 中文 + 日常编码。
需要 gcc/make 等**完整 Linux 编译工具链**、或跑 ROS 时，官方推荐 WSL2（真 Linux 内核），Claude Code 在 WSL 里安装，体验和纯 Linux 完全一致。

## 参考

- https://code.claude.com/docs/en/setup
- https://code.claude.com/docs/en/env-vars
- https://code.claude.com/docs/en/tools-reference
