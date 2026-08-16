# lima — 開発環境構築・運用リポジトリ

macOS ホスト上に [Lima](https://lima-vm.io/) で開発用 VM を構築・運用するための専用リポジトリ。
開発プロジェクトのソースコードはここには置かず、各 VM(ゲスト)内で別リポジトリとして管理する。

## 方針(設計判断の要約)

- **cattle 運用**: VM は使い捨て前提。`make` で同じ環境をゼロから再現できる状態を常に維持する。
  ゲストに何かをインストールしたら provisioning に追記するのがルール。
- **3層構成**:
  1. `lima.yaml` — VM の器の定義(リソース、イメージ、SSH 設定)
  2. `provision`(lima.yaml 内)— ゲスト OS 内部の構成。毎起動実行されるため冪等に書く
  3. `make setup` — SSH 経由の起動後処理(エージェント転送が必要な作業はここ)
- **パッケージの使い分け**: システム基盤(Docker 等のデーモン系)は apt、開発ツールは Homebrew
- **マウントなし**: ホスト→ゲストの writable マウントはしない。コードはゲスト内で完結し、
  こまめに push する(`make check-dirty` が破棄前の安全網)
- ブラウザでの動作確認は Lima の自動ポートフォワード(localhost)、内部ドメインは SOCKS プロキシ経由

詳細な設計判断・計画は [Issues](https://github.com/kamitsui/lima/issues) を参照。

## 構成

```
.
├── Makefile          # 環境の構築・起動・停止など(ENV で環境を指定)
└── envs/
    └── debian-web/   # Web 開発用 Debian 13 環境
        └── lima.yaml
```

## 前提条件

- macOS(Apple Silicon)
- Homebrew
- Lima(`brew install lima`)

## 初期設定(初回のみ)

`~/.ssh/config` の先頭に以下を追加する(パスは clone 先に合わせる):

```
Include ~/Documents/42staff/lima/ssh/config

# 鍵の使用時に自動で ssh-agent へ登録(ゲストへのエージェント転送で必要)
Host *
	AddKeysToAgent yes
```

接続設定の実体は本リポジトリの [`ssh/config`](ssh/config) にあり、ポート等は
Lima 生成の `~/.lima/*/ssh.config` に自動追従する。接続は wezterm 等から:

```sh
ssh lima-debian-web   # ForwardAgent / DynamicForward 1080 / COLORTERM 伝搬つき
```

`make ssh`(limactl shell)は管理用の簡易接続。開発時は上記の ssh 接続を常用する。

## データの永続化(何が残り、何が消えるか)

VM は使い捨て(`make delete` / `make recreate`)が前提。何が残るかは次の通り:

**残るもの**
- 永続データディスク `web-data` 上のデータ: `~/.claude` と `~/.claude.json`
  (Claude Code のログイン・履歴・メモリ)。対象パスは lima.yaml の
  provisioning 内 dirs / files リストで管理し、必要に応じて追記する
- push 済みの git リポジトリ(GitHub 側に存在するもの)
- ホスト側の設定(ssh 設定、Lima のイメージキャッシュ、このリポジトリ)

**消えるもの**
- 上記以外のゲスト内すべて: ホームの作業ファイル、Docker イメージ/volume、
  /etc/hosts への追記、provisioning に書かず手動インストールしたもの
- 未 push のコミット・未コミットの変更(破棄前の検出は make check-dirty で整備予定)

**データディスクのハマりどころ**(実際に踏んだもの)
- **raw 形式で作ること**。qcow2 だと vz の起動時変換でデータが消える(`make disk` は対応済み)
- **ディスク名は 11 文字以内**。Lima のフォーマット済み判定は ext4 ラベル
  `lima-<名前>`(16 文字で切り詰め)に依存するため、超えると毎起動初期化される
- ディスクごと消す完全リセットは `make delete-data`(確認プロンプト付き)

## ブラウザでの動作確認(2 経路)

**日常は localhost、ドメインで検証したいときは SOCKS** と使い分ける。

### 1. localhost(自動ポートフォワード)

ゲストで listen したポートは自動でホストの localhost に転送される。
ゲストで `:3000` のサービス → ホストのブラウザで `http://localhost:3000`。
macOS は特権ポートも bind できるため `:80` もそのまま転送される。

### 2. SOCKS プロキシ(内部ドメインでの検証)

`ssh lima-debian-web` の接続中、ホストの `localhost:1080` が SOCKS v5 プロキシになる。
**SOCKS は ssh 接続の「副作用」として提供される**ため、専用の操作は不要:
開発中は普通 ssh セッションを開いているので、そのあいだ Firefox からずっと使える。
接続が 1 本もない間は 1080 は閉じる(curl が `Could not connect` になるのはこの状態)。
対話セッションなしでトンネルだけ欲しいときは `ssh -f -N lima-debian-web` を使う。
複数セッション同時接続では 2 本目以降に bind の警告が出るが無害(1 本目が 1080 を担当)。

名前解決はゲスト側で行われるため、**ゲストの /etc/hosts に書いたドメインがそのまま使える**。
なおゲスト内からは SOCKS を介す必要はなく `curl http://app.test/` で直接届く:

```sh
# ゲスト側: ドメインを定義
echo '127.0.0.1 app.test' | sudo tee -a /etc/hosts
# ホスト側: curl での確認(--socks5-hostname がリモート DNS 相当)
curl --socks5-hostname 127.0.0.1:1080 http://app.test/
```

Firefox は専用プロファイルを作って使う(初回のみ):

1. `about:profiles` で新規プロファイル(例: `lima-dev`)を作成して起動
2. 設定 → ネットワーク設定 → 手動プロキシー設定
   - SOCKS ホスト: `localhost`、ポート: `1080`、**SOCKS v5** を選択
   - **「SOCKS v5 を使用するときは DNS もプロキシーを使用する」に必ずチェック**(これが無いとゲストのドメインを解決できない)
3. localhost 宛は既定でプロキシを経由しないため、OAuth コールバック等とは干渉しない

ワイルドカード(`*.test`)が必要になったらゲストに dnsmasq を追加する(未導入)。

## 使い方

```sh
make help     # ターゲット一覧
make up       # VM を作成(初回)または起動(既定 ENV=debian-web)
make ssh      # VM に接続
make down     # 停止
make status   # 状態表示
make delete   # 破棄(確認あり)
make recreate # 破棄して作り直し(確認あり)
```

別環境を追加した場合は `make up ENV=<環境名>` のように指定する。
