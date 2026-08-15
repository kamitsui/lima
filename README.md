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
