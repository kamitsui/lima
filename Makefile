# 開発環境(Lima VM)の構築・運用
# 対象環境は ENV で指定する(例: make up ENV=debian-web)

ENV ?= debian-web
LIMA_YAML := envs/$(ENV)/lima.yaml

.PHONY: up down ssh status delete

up: ## VM を作成(初回)または起動
	@if limactl list --quiet 2>/dev/null | grep -qx '$(ENV)'; then \
		limactl start $(ENV); \
	else \
		limactl create --name=$(ENV) --tty=false $(LIMA_YAML) && limactl start $(ENV); \
	fi

down: ## VM を停止
	limactl stop $(ENV)

ssh: ## VM に接続
	limactl shell $(ENV)

status: ## VM の状態を表示
	limactl list

delete: ## VM を破棄(確認あり)
	@printf 'VM "%s" を削除します。よろしいですか? [y/N] ' '$(ENV)'; \
	read ans; [ "$$ans" = "y" ] || { echo '中止しました'; exit 1; }; \
	limactl delete --force $(ENV)
