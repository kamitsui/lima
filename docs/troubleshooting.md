# トラブルシュート

実際に踏んだ問題と対処の記録。症状から引けるように並べている。
各問題の調査経緯は対応する Issue のコメントに詳細がある。

## 構築直後

### `make ssh` で docker が permission denied(初回構築直後のみ)
Lima の SSH ControlMaster が provisioning(docker グループ追加)より先に確立される
ため、その接続経由のセッションには古いグループ情報が残る。
**対処**: `ssh lima-debian-web`(独立接続)を使えば最初から問題ない。
`make ssh` を使いたい場合は一度 `make down && make up`。(#3, #6)

### 構築直後にツール(nvim, ghq 等)がまだ無い
Lima の READY 判定はユーザーモード provisioning の完了を待たないため、
brew ツールの導入は READY 後も数分バックグラウンドで続く。
**対処**: 待つだけ。`make setup` は必要ツールが揃うまで自動で待機する。(#4)

### lima.yaml を変更したのに反映されない
インスタンスは**作成時の yaml のコピー**(`~/.lima/<env>/lima.yaml`)で動く。
リポジトリ側の変更は自動では反映されない。
**対処**: `limactl stop <env> && cp envs/<env>/lima.yaml ~/.lima/<env>/lima.yaml && limactl start <env>`、
または `make recreate`(cattle 的にはこちらが正道)。

## 接続・表示

### 対話 SSH ログインに数秒かかる
Lima 2.x の vsock SSH は接続元 IP が無く、sshd が接続元を文字列 `UNKNOWN` と
記録する。対話ログイン時にこれが DNS 解決に回り、タイムアウトまで待たされる。
**対処**: provisioning が `/etc/hosts` に `127.0.0.1 UNKNOWN` を入れて解決済み。
再発したらこの行の有無を確認。(#6 に調査記録: 4.1s → 0.13s)

### `Last login: ... from UNKNOWN` と表示される
vsock 接続の正常な表示(接続元 IP が存在しないため)。問題ではない。

### journal に `syslogin_perform_logout: logout() returned an error`
Debian 13 が utmp を廃止(Y2038 対応)した影響。無害。

### truecolor が効かない(nvim の色が濁る)
確認: ゲストで `echo $COLORTERM` → `truecolor` が出るか。出ない場合は
ホスト側 `SendEnv COLORTERM`(ssh/config)とゲスト側 `AcceptEnv`(provisioning)を確認。
表示テスト(グラデーションが滑らかなら OK。縞状なら 256 色に劣化):
```sh
awk 'BEGIN{for(i=0;i<77;i++){r=255-i*3;g=i*6;b=i*3;if(g>255)g=510-g;printf "\033[48;2;%d;%d;%dm.",r,g,b}print "\033[0m"}'
```
`TERM=wezterm` が解決できない場合は wezterm terminfo(provisioning 導入)を確認。(#6)

### `make ssh` と `ssh lima-debian-web` で見た目が違う
`make ssh`(limactl shell)は Lima 設定のシェル(bash)で起動し motd も出ない管理用。
`ssh lima-debian-web` が /etc/passwd のログインシェル(zsh + starship)で起動する
正規経路。**開発時は後者を常用**する。

### プロンプトのホームディレクトリが空に見える
starship の `home_symbol` が Nerd Font の家アイコンのため、フォントや
コピペ環境によっては見えない。異常ではない。

## ブラウザ・ネットワーク

### SOCKS(localhost:1080)に繋がらない
SOCKS は `ssh lima-debian-web` の**接続中だけ**存在する(ssh クライアントの機能)。
セッションを全部閉じると消える。トンネルだけ欲しいときは `ssh -f -N lima-debian-web`。
複数セッション時の 2 本目以降の bind 警告は無害。(#7)
なおゲスト内から SOCKS は使えない(不要。/etc/hosts が直接効く)。

### ポートがホストに転送されない
Lima はゲストで listen したポートを自動でホスト 127.0.0.1 に転送する。
- ゲスト側で本当に listen しているか: `ss -tlnp`
- ホスト側で同じポートを別プロセスが使っていると転送に失敗する(lima のログに警告)
- macOS は特権ポート(:80 等)も bind できるため、80 もそのまま転送される

### OAuth 認証(Claude Code 等)がブラウザで完了しない
localhost コールバック型はゲストで listen したポートが自動転送されるので通る。
Claude Code は SSH 環境では「認証コードをターミナルに貼り付け」が標準経路
(コールバック不要)。Firefox は既定で localhost をプロキシに通さないので
SOCKS 設定とも干渉しない。(#8)

## パッケージ・ツール

### brew install がソースビルドになって遅い
ARM64 Linux は Tier 1 だが、マイナー formula は bottle が無いことがある。
**対処**: その formula だけ apt にフォールバックする。

### vim 起動時に E117: Unknown function plug#begin
vim-plug 本体が無いマシンで起きる。plugins.vim に自動ダウンロードのガードが
あるので通常は自己解決する。`make setup` も明示的に導入する。

### /tmp に大きいファイルを置くとメモリを圧迫する
Debian 13 から /tmp は tmpfs(RAM の 50%)。巨大な一時ファイルは
`~/tmp` 等ディスク上に置く。

## 永続データディスク

### ディスクの中身が消えた / 毎回初期化される
過去に踏んだ原因は 2 つ(いずれも対策済み。再発時はここを確認):
1. **qcow2 形式で作った** — vz は起動時に raw へ変換し、その過程でデータが
   消える(lima#1964)。`--format raw` で作ること(`make disk` は対応済み)
2. **ディスク名が 11 文字を超えた** — Lima のフォーマット済み判定は ext4 ラベル
   `lima-<名前>` の存在チェックだが、ラベルは 16 文字に切り詰められるため
   一致せず毎起動「初回」と誤判定される。名前は 11 文字以内に(#15 に調査記録)

### ディスクの中身を確認したい
VM 起動中に `ssh lima-debian-web 'ls -la /mnt/lima-web-data/dev/'`。
macOS からは直接読めない(ext4)。VM が壊れた場合も、別 VM に
additionalDisks でアタッチすれば読める。

## dotfiles / stow

### stow が「existing target is not owned by stow」で失敗する
- stow 管理のリポジトリを**移動**するとリンクの相対パスが変わって全滅する。
  移動前に `make uninstall`(unstow)してから移動 → 再 stow(setup.sh の移行処理は対応済み)
- **ランタイム生成物**(.zcompdump, vim の plugged 等)がパッケージ内に
  あると、ターゲット側の生成物と衝突する。パッケージには追跡ファイルだけを置く

### ディレクトリ丸ごとリンク(fold)による事故
ターゲットにディレクトリが無いと stow はディレクトリごとリンクし、
ランタイム生成物がパッケージ内に書き込まれてしまう。
dotfiles の `make install` は `~/.config` と `~/.vim` を実ディレクトリとして
事前作成して防止している。

## その他

### amd64 コンテナが動かない(Rosetta)
カーネル 6.11 以降の vDSO 変更に Rosetta が未対応(Apple 側のバグ、
`Failed to find vdso DT_HASH`)。ホスト macOS 14.5 時点では実行不可。
代替手段と状況は #13 を参照。

## 参考: ゲストの df -h の読み方

一見複雑だが、実ディスクは vda(システム)と vdb(永続データ)だけ:

| 表示 | 正体 |
|---|---|
| `/dev/vda1` (99G, /) | ルート。cloud イメージを growpart が初回起動時に自動拡張。単一パーティションが cloud の標準 |
| `/dev/vda15` (/boot/efi) | UEFI ブート用 ESP(vz は EFI ブート) |
| `/dev/vdb1` (/mnt/lima-web-data) | 永続データディスク |
| `/mnt/lima-cidata` (20M, 100%) | provisioning スクリプトの運搬路。毎起動 Lima が再生成(100% 使用で正常) |
| `vz-rosetta` (/mnt/lima-rosetta) | ホストの Rosetta 共有。数字は**ホスト側ディスク**の統計 |
| `tmpfs` 群(/run, /dev/shm, /tmp 等) | RAM 上。**/tmp は Debian 13 から tmpfs(RAM の 50%)** |
