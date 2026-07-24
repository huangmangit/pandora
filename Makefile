.PHONY: core-up core-down up-all down-all ps logs-core \
        up-personal down-personal up-company-a down-company-a \
        up-outsource-a down-outsource-a

# ═══ 核心服务 ═══
core-up:
	docker compose -f core/docker-compose.yml up -d

core-down:
	docker compose -f core/docker-compose.yml down

logs-core:
	docker compose -f core/docker-compose.yml logs -f

# ═══ 全局 ═══
up-all:
	docker compose up -d

down-all:
	docker compose down

ps:
	docker compose ps

# ═══ 分组操作 ═══
up-personal:
	docker compose -f apps/personal/docker-compose.yml up -d

down-personal:
	docker compose -f apps/personal/docker-compose.yml down

up-company-a:
	docker compose -f apps/company-a/docker-compose.yml up -d

down-company-a:
	docker compose -f apps/company-a/docker-compose.yml down

up-outsource-a:
	docker compose -f apps/outsource-a/docker-compose.yml up -d

down-outsource-a:
	docker compose -f apps/outsource-a/docker-compose.yml down
