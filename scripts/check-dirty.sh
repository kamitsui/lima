#!/bin/bash
# ghq 管理下の全リポジトリを走査し、退避されていない作業を検出する
# (未コミットの変更・未 push のコミット・stash)
# ホストの `make check-dirty` から SSH 経由で実行される。dirty があれば exit 1
set -u

[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

if ! command -v ghq >/dev/null 2>&1; then
  echo "ghq 未導入(セットアップ前)のため検査をスキップします"
  exit 0
fi

root="$(ghq root)"
dirty=0

for repo in $(ghq list 2>/dev/null); do
  dir="$root/$repo"
  [ -d "$dir/.git" ] || continue
  problems=()

  # 未コミットの変更(未追跡ファイルを含む)
  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    problems+=("未コミットの変更")
  fi

  # 未 push のコミット(全ローカルブランチのうち、どのリモートにも無いもの)
  unpushed=$(git -C "$dir" log --branches --not --remotes --oneline 2>/dev/null | wc -l)
  if [ "$unpushed" -gt 0 ]; then
    problems+=("未 push のコミット ${unpushed} 件")
  fi

  # stash
  stashes=$(git -C "$dir" stash list 2>/dev/null | wc -l)
  if [ "$stashes" -gt 0 ]; then
    problems+=("stash ${stashes} 件")
  fi

  if [ ${#problems[@]} -gt 0 ]; then
    dirty=1
    echo "✗ $repo: ${problems[*]}"
  fi
done

if [ "$dirty" = 1 ]; then
  echo ""
  echo "退避されていない作業があります。push(または退避)してから破棄してください"
  exit 1
fi

echo "✓ ghq 管理下の全リポジトリはクリーン(push 済み)"
