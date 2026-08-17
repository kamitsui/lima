# 設計判断の記録

「なぜこうしたか」の記録。経緯の詳細は各 Issue の本文・コメントにある。

## 1. cattle 運用(VM は使い捨て)

**決定**: VM 内に再現できない状態を作らない。`make recreate && make setup` で
ゼロから同じ環境に戻れることを常に維持する。

**理由**: バックアップ・スナップショット運用(pet)は「この環境どう作ったか
分からない」負債になりがち。コード化しておけば Debian や Lima の更新も
「新しく作って乗り移る」だけで済む。

**帰結(三層の安全網)**: コードは check-dirty(未 push 検出)が守り、
状態データは永続ディスクが守り、環境そのものは provisioning が再現する。

## 2. 3 層構成(lima.yaml / provision / make setup)

| 層 | 実行場所 | 担当 |
|---|---|---|
| lima.yaml 本体 | ホスト(limactl) | VM の器(リソース、イメージ、SSH 設定) |
| provision セクション | ゲスト内(毎起動) | OS 構成(apt、docker、brew、ツール) |
| make setup | ホスト→SSH 経由 | 認証が要る処理(private リポジトリの clone 等) |

**理由**: provisioning 実行中は SSH エージェント転送が使えないため、
認証が必要な処理は起動後の SSH 経由に分離する必要がある。
provision スクリプトは毎起動実行されるため、すべて冪等に書く。

## 3. apt と Homebrew の使い分け

**決定**: システム基盤(docker-ce 等のデーモン・systemd 連携が必要なもの)は apt、
開発ツール(vim, fzf, ghq...)は Homebrew。

**理由**: brew は systemd サービス管理に不向き。逆に開発ツールは brew の方が
新しく、ARM64 Linux も bottle 提供(Tier 1)されている。

## 4. ホスト→ゲストの writable マウントを持たない

**決定**: コードはゲスト内で完結させ、ホストのディレクトリをマウントしない。

**理由**: 本リポジトリは環境構築専用で、開発コードは別リポジトリとして
ゲスト内に clone する運用。マウントを無くすことで virtiofs の性能問題・
権限問題が構成から消える。Docker の bind mount もネイティブ速度になる。

## 5. ブラウザ動作確認の 2 経路(localhost / SOCKS)

**決定**: 日常は Lima の自動ポートフォワード(http://localhost:PORT)、
ドメイン名での検証時だけ SOCKS(DynamicForward 1080)を使う。

**理由**: SOCKS v5 のリモート DNS 解決により、ゲストの /etc/hosts に書いた
ドメイン(app.test 等)がホストの Firefox からそのまま使える。名前解決も
接続もゲスト側で行われるため、ポート開放の追加設定が不要。
OAuth コールバック等の localhost 通信は自動転送で足りる(Firefox は既定で
localhost をプロキシに通さないため干渉しない)。

## 6. ゲストユーザーは汎用名 dev(#14)

**決定**: Lima 既定の「ホストのアカウント複製」をやめ、全環境共通の `dev` にする。

**理由**: 既定ではユーザー名に加え GECOS にフルネームまで複製される。
ゲストで AI エージェントを動かす前提のため、個人特定情報をゲストから排除する。
環境の識別はインスタンス名・ホスト名が担う。同じ理由で、コミットメッセージ等の
成果物にも個人特定情報を書かない(公開 identity である GitHub アカウント名は可)。

## 7. 永続データディスク(#15)

**決定**: `limactl disk` の名前付きディスク(web-data, raw, 20GiB)を
additionalDisks でアタッチし、状態データ(~/.claude, ~/.claude.json)を
symlink で退避する。対象は lima.yaml の dirs/files リストで管理。

**理由**: 設定は dotfiles で再現できるが、状態(認証・履歴・メモリ)は
再現できない。「VM は使い捨て、データは名前付きディスク」の分離は
Docker volume と同じ発想。バックアップ方式(取り忘れリスク)や
ホストマウント方式(マウントなし方針の例外化)より筋が良い。

**制約(実測で判明)**: ①raw 必須(qcow2 は vz の起動時変換で消える)
②ディスク名 11 文字以内(ext4 ラベル 16 文字制限にフォーマット済み判定が依存)

## 8. dotfiles は単一リポジトリで mac / Debian 共通

**決定**: OS ごとに分けず、既存の dotfiles リポジトリを拡張して共通化。
stow パッケージ + OS 差分は os-macos / os-debian パッケージ(os.zsh)で吸収。
プラグインは git submodule でバージョン固定。

**理由**: リポジトリを分けると改善のたびに二重メンテになり確実にドリフトする。
実際の OS 差分は brew のパス(zshenv の候補ループで解決)と数個の
ビルドフラグ程度しかない。

**運用ルール**: 秘密情報は secrets.zsh(git 管理外)へ。ランタイム生成物を
パッケージ内に置かない。~/.local/bin や brew の PATH は ~/.zshenv に置く
(非対話 ssh コマンドでも効くように)。

## 9. ssh 設定は Include の 2 段構え

**決定**: `~/.ssh/config` には Include 1 行だけ。実体はリポジトリの
`ssh/config`(オプション)+ Lima 生成の `~/.lima/*/ssh.config`(接続情報)を
glob Include。

**理由**: ポートは再構築のたびに変わるが、glob Include で自動追従する。
オプション(ForwardAgent / DynamicForward / SendEnv COLORTERM /
ControlMaster 無効)は version 管理される。ControlMaster を切るのは
Lima 内部の多重化に相乗りすると初回構築時のグループ反映等で不整合が
出るため(独立接続なら常に最新状態)。

## 10. リポジトリは ghq 規約で一元管理

**決定**: ゲスト内の全リポジトリ(dotfiles 含む)を `~/ghq/github.com/<owner>/<repo>`
に統一。`~/.dotfiles` は symlink。移動は Ctrl-G(fzf ウィジェット)。

**理由**: 「探すのではなく置き場所を規約で固定する」。全数把握が `ghq list`
一発になり、check-dirty(破棄前の未 push 検査)が全リポジトリを漏れなく守れる。
