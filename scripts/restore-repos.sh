#!/bin/bash
# 永続ディスクに保存されたリポジトリ一覧(check-dirty が自動保存)から、
# 未 clone のリポジトリを ghq get で一括復元する(冪等)
# ホストの `make restore-repos` から SSH 経由で実行される
set -eu -o pipefail

[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
export PATH="$HOME/.local/bin:$PATH"

LIST=/mnt/lima-web-data/dev/ghq-repos.list
if [ ! -f "$LIST" ]; then
  echo "保存されたリポジトリ一覧がありません($LIST)"
  echo "(一覧は make check-dirty / delete / recreate の際に自動保存されます)"
  exit 0
fi

root="$(ghq root)"
restored=0 skipped=0 failed=0

while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  if [ -d "$root/$repo/.git" ]; then
    skipped=$((skipped + 1))
    continue
  fi
  echo "clone: $repo"
  if ghq get -p "$repo" >/dev/null 2>&1; then
    restored=$((restored + 1))
  else
    echo "  ✗ 失敗: $repo(アクセス権・エージェント転送を確認)"
    failed=$((failed + 1))
  fi
done < "$LIST"

echo "復元 ${restored} 件 / 既存 ${skipped} 件 / 失敗 ${failed} 件"
[ "$failed" = 0 ]
