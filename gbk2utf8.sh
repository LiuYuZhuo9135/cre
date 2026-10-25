#!/usr/bin/env bash
# gbk2utf8.sh —— 把目录下的 GBK 文本文件批量转成 UTF-8
#
# 用法：
#   ./gbk2utf8.sh              转换当前目录及子目录，保留 .bak 备份
#   ./gbk2utf8.sh --dry-run    只列出会转换哪些文件，不真正修改
#   ./gbk2utf8.sh --no-backup  转换且不保留 .bak 备份
#
# 依赖：iconv（Linux 自带；Windows 的 Git Bash 也自带）
# 源编码默认 GB18030（GBK/GB2312 的超集，能正确解码常见中文文件）

set -euo pipefail

# 要处理的文本扩展名（按需增删）
EXTS=(txt md c h cpp hpp py sh json yaml yml xml csv html css js ts java go rs)
SRC="GB18030"

DRY_RUN=0
BACKUP=1
for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=1 ;;
    --no-backup) BACKUP=0 ;;
    *) echo "未知参数: $arg" >&2; exit 2 ;;
  esac
done

# 判断文件是否已是合法 UTF-8
is_utf8() {
  iconv -f UTF-8 -t UTF-8 "$1" > /dev/null 2>&1
}

# 构建 find 的 -name 条件：-name "*.txt" -o -name "*.md" ...
name_args=()
for e in "${EXTS[@]}"; do
  name_args+=(-name "*.$e" -o)
done
name_args=("${name_args[@]:0:${#name_args[@]}-1}")  # 去掉末尾的 -o

converted=0
failed=0

while IFS= read -r -d '' f; do
  if is_utf8 "$f"; then
    :  # 已是 UTF-8，跳过
  else
    echo "转换: $f"
    if [ "$DRY_RUN" -eq 0 ]; then
      tmp="$f.utf8tmp"
      if iconv -f "$SRC" -t UTF-8 "$f" > "$tmp" 2>/dev/null; then
        [ "$BACKUP" -eq 1 ] && cp "$f" "$f.bak"
        mv "$tmp" "$f"
      else
        rm -f "$tmp"
        echo "  跳过（无法按 $SRC 解码，可能非文本）: $f"
        failed=$((failed+1))
      fi
    fi
    converted=$((converted+1))
  fi
done < <(find . -type f \( "${name_args[@]}" \) -print0)

echo ""
echo "完成：需转换 $converted 个文件，失败 $failed 个。"
[ "$DRY_RUN" -eq 1 ] && echo "（--dry-run 模式，未真正修改）"
