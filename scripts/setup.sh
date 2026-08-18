#!/bin/bash
# ゲストのユーザーレベル仕上げ(ホストの `make setup` から SSH 経由で実行される)
# 何度実行しても安全(冪等)。SSH エージェント転送が必要な処理はここに置く
set -eu -o pipefail

# 非対話 bash のため brew と ~/.local/bin の PATH を自前で通す
[ -x /home/linuxbrew/.linuxbrew/bin/brew ] && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
export PATH="$HOME/.local/bin:$PATH"

# 初回構築直後は brew ツールの導入(ユーザー層 provisioning)がバックグラウンドで
# 継続していることがあるため、必要なコマンドが揃うまで待つ(最大10分)
for i in $(seq 1 60); do
  if command -v stow >/dev/null 2>&1 && command -v ghq >/dev/null 2>&1; then break; fi
  [ "$i" = 1 ] && echo "brew ツールの導入完了を待機中(初回構築時は数分かかります)..."
  [ "$i" = 60 ] && { echo "error: brew ツールが揃いませんでした(provisioning のログを確認)" >&2; exit 1; }
  sleep 10
done

# dotfiles: ghq の標準階層に配置し、~/.dotfiles からシンボリックリンク
DOT_DIR="$(ghq root)/github.com/kamitsui/dotfiles"
if [ ! -d "$DOT_DIR/.git" ]; then
  if [ -d "$HOME/.dotfiles/.git" ] && [ ! -L "$HOME/.dotfiles" ]; then
    # 旧配置(実ディレクトリ)からの移行。リンクの相対パスが変わるため
    # 移動前に unstow しておく(移動後に make install で張り直す)
    (cd "$HOME/.dotfiles" && make uninstall >/dev/null 2>&1) || true
    mkdir -p "$(dirname "$DOT_DIR")"
    mv "$HOME/.dotfiles" "$DOT_DIR"
  else
    ghq get -p kamitsui/dotfiles
  fi
fi
[ -L "$HOME/.dotfiles" ] || ln -sn "$DOT_DIR" "$HOME/.dotfiles"

cd "$DOT_DIR"
git pull --ff-only 2>/dev/null || echo "warning: dotfiles の pull をスキップしました"
make install

# vim プラグインの事前インストール(初回起動時の待ちを無くす)
# vim 内の自動ダウンロードに頼らず、plug.vim を明示的に取得してから実行する
if command -v vim >/dev/null 2>&1; then
  if [ ! -f "$HOME/.vim/autoload/plug.vim" ]; then
    curl -sfLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  fi
  vim -es -u "$HOME/.vimrc" +'PlugInstall --sync' +qall! >/dev/null 2>&1 || true
fi

echo "== setup 完了 =="
echo "dotfiles : $(git -C "$DOT_DIR" log --oneline -1)"
command -v starship >/dev/null 2>&1 && echo "zsh      : starship / プラグイン OK"
if [ -f "$HOME/.claude/.credentials.json" ]; then
  echo "claude   : ログイン済み(永続ディスク上)"
else
  echo "claude   : 未ログイン → ゲストで claude を実行して認証してください"
fi
LIST=/mnt/lima-web-data/dev/ghq-repos.list
if [ -f "$LIST" ]; then
  missing=0
  while IFS= read -r r; do
    [ -n "$r" ] && [ ! -d "$(ghq root)/$r/.git" ] && missing=$((missing + 1))
  done < "$LIST"
  if [ "$missing" -gt 0 ]; then
    echo "repos    : 未復元 ${missing} 件 → make restore-repos で一括復元できます"
  else
    echo "repos    : 保存済み一覧はすべて復元済み"
  fi
fi
