# 開発環境(Lima VM)の構築・運用
# 対象環境は ENV で指定する(例: make up ENV=debian-web)

ENV ?= debian-web
LIMA_YAML := envs/$(ENV)/lima.yaml
# ディスク名は 11 文字以内にすること(Lima は ext4 ラベル "lima-<名前>" で
# フォーマット済み判定をするが、ラベルは 16 文字で切り詰められるため、
# 超えると毎起動re-フォーマットされデータが消える)
DATA_DISK ?= web-data

.DEFAULT_GOAL := help
.PHONY: help up down ssh status delete recreate disk delete-data setup check-dirty _dirty_guard restore-repos

help: ## ターゲット一覧を表示
	@grep -E '^[a-z][a-zA-Z_-]*:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

disk: ## 永続データディスクを作成(存在しなければ)
	@# 注意: vz は raw のみ対応。qcow2 で作ると起動時変換でデータが消える(lima#1964)
	@limactl disk list 2>/dev/null | awk 'NR>1{print $$1}' | grep -qx '$(DATA_DISK)' || \
		limactl disk create $(DATA_DISK) --size 20GiB --format raw

up: disk ## VM を作成(初回)または起動
	@if limactl list --quiet 2>/dev/null | grep -qx '$(ENV)'; then \
		limactl start $(ENV); \
	else \
		limactl create --name=$(ENV) --tty=false $(LIMA_YAML) && limactl start $(ENV); \
	fi

down: ## VM を停止
	limactl stop $(ENV)

setup: ## 起動後のユーザーレベル仕上げ(dotfiles 導入等。冪等・要エージェント転送)
	ssh lima-$(ENV) 'bash -s' < scripts/setup.sh

ssh: ## VM に接続
	limactl shell $(ENV)

status: ## VM の状態を表示
	limactl list

check-dirty: ## ゲスト内リポジトリの未 push・未コミットを検査(+ 一覧を自動保存)
	@ssh lima-$(ENV) 'bash -s' < scripts/check-dirty.sh

restore-repos: ## 保存された一覧からリポジトリを一括復元(未 clone 分のみ)
	@ssh lima-$(ENV) 'bash -s' < scripts/restore-repos.sh

# 破棄系ターゲットの前段検査。dirty なら中断(FORCE=1 でスキップ可)
_dirty_guard:
	@if [ "$(FORCE)" = "1" ]; then \
		echo 'FORCE=1: dirty 検査をスキップします'; \
	elif limactl list $(ENV) --format '{{.Status}}' 2>/dev/null | grep -qx Running; then \
		$(MAKE) --no-print-directory check-dirty ENV=$(ENV) || \
			{ echo ''; echo '破棄を中止しました(FORCE=1 で強制続行できます)'; exit 1; }; \
	else \
		echo '警告: VM が起動していないため dirty 検査をスキップします(検査するには make up)'; \
	fi

delete: _dirty_guard ## VM を破棄(dirty 検査 + 確認あり。データディスクは残る)
	@printf 'VM "%s" を削除します。よろしいですか? [y/N] ' '$(ENV)'; \
	read ans; [ "$$ans" = "y" ] || { echo '中止しました'; exit 1; }; \
	limactl delete --force $(ENV)

recreate: _dirty_guard ## VM を破棄して作り直す(dirty 検査 + 確認あり)
	@printf 'VM "%s" を削除して作り直します。よろしいですか? [y/N] ' '$(ENV)'; \
	read ans; [ "$$ans" = "y" ] || { echo '中止しました'; exit 1; }; \
	limactl delete --force $(ENV) && $(MAKE) up ENV=$(ENV)

delete-data: ## 永続データディスクを完全削除(状態データが消える。確認あり)
	@printf 'データディスク "%s" を完全削除します。Claude Code の履歴等が失われます。よろしいですか? [y/N] ' '$(DATA_DISK)'; \
	read ans; [ "$$ans" = "y" ] || { echo '中止しました'; exit 1; }; \
	limactl disk delete $(DATA_DISK)
