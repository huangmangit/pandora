# Pandora Docker 服务

本项目使用根目录的 `docker-compose.yml` 管理 PHP-FPM、数据库及辅助服务。以下说明以该文件为准；目录中现存的 Caddy、OpenResty 配置和 `woodpecker/docker-compose.yml` 不属于根 Compose 的服务。

## 服务与端口

| 服务              | 镜像或构建                               | 宿主机端口 → 容器端口         | 用途            |
| ----------------- | ---------------------------------------- | ----------------------------- | --------------- |
| php74             | `php/7.4/Dockerfile`                     | 未发布                        | PHP 7.4 FPM     |
| php83             | `php/8.3/Dockerfile`                     | 未发布                        | PHP 8.3 FPM     |
| mariadb           | `mariadb:11.8`                           | 3306 → 3306                   | MariaDB         |
| postgres          | `postgres:18.4-alpine`                   | `${POSTGRES_PORT}` → 5432     | PostgreSQL      |
| redis             | `redis:8.8.1`                            | 6379 → 6379                   | Redis           |
| dbx               | `t8y2/dbx`                               | 14224 → 4224                  | 数据库管理工具  |
| dpanel            | `dpanel/dpanel:1.10.6`                   | `${DPANEL_PORT:-8807}` → 8080 | Docker 管理面板 |
| woodpecker-server | `woodpeckerci/woodpecker-server:v3.16.0` | 8000 → 8000，9000 → 9000      | CI 服务端       |
| woodpecker-agent  | `woodpeckerci/woodpecker-agent:v3.16.0`  | 未发布                        | CI 执行器       |
| vaultwarden       | `vaultwarden/server:latest`              | 11001 → 80                    | 密码管理服务    |

PHP-FPM 没有直接发布 HTTP 端口，需要另行配置 Web 服务器。根 Compose 没有启动 Caddy 或 OpenResty。

## 准备与启动

需要安装 Docker 和 Docker Compose 插件。首次使用时准备环境变量，并检查端口是否可用：

```sh
cp .env.example .env
# 编辑 .env，替换示例密码和 Woodpecker 配置
```

如果已有 `.env`，保留并编辑现有文件，不要覆盖。Compose 引用两个外部网络，须事先存在：

```sh
docker network inspect 1panel-network >/dev/null 2>&1 || docker network create 1panel-network
docker network inspect pandora-net >/dev/null 2>&1 || docker network create pandora-net
docker compose config --quiet
docker compose up -d --build
```

也可以只启动所需服务，例如 `docker compose up -d --build php83 mariadb redis`。Compose 不会自动为 Woodpecker 创建 GitHub OAuth 应用；使用前需在 `.env` 中配置外部访问地址、GitHub OAuth 凭据、管理员用户名、Agent 地址及共享密钥。

## 环境变量

| 变量                                                                       | 用途                                                      |
| -------------------------------------------------------------------------- | --------------------------------------------------------- |
| `MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`                                    | MariaDB root 密码及初始数据库                             |
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`                        | PostgreSQL 用户、密码及初始数据库；Compose 分别提供默认值 |
| `POSTGRES_PORT`                                                            | PostgreSQL 宿主机端口；需在 `.env` 中设置                 |
| `DPANEL_PORT`                                                              | DPanel 宿主机端口，默认 8807                              |
| `WOODPECKER_HOST`, `WOODPECKER_SERVER`                                     | CI 外部访问地址及 Agent 连接地址                          |
| `WOODPECKER_AGENT_SECRET`, `WOODPECKER_AGENT_LABEL`                        | Agent 共享密钥及节点标签                                  |
| `WOODPECKER_ADMIN`, `WOODPECKER_GITHUB_CLIENT`, `WOODPECKER_GITHUB_SECRET` | 管理员及 GitHub OAuth 配置                                |

`.env.example` 中还包含一些当前根 Compose 未引用的变量；例如 `REDIS_PASSWORD` 不会自动配置 Redis 密码，Redis 的实际设置来自 `redis/redis.conf`。PostgreSQL 服务还通过 `env_file` 将 `.env` 传入容器。

## 目录与持久化

```text
.
├── docker-compose.yml
├── .env.example
├── php/
│   ├── 7.4/Dockerfile
│   ├── 8.3/Dockerfile
│   └── conf.d/              # FPM 监听及 PHP 时区配置
├── mysql/conf.d/           # MariaDB 配置
├── mysql/init/             # MariaDB 初始化脚本
├── redis/redis.conf
├── dbx-data/               # DBX 数据
├── woodpecker/agent-data/  # Agent 数据目录
├── vaultwarden/            # Vaultwarden 数据
└── log/                    # PostgreSQL 日志挂载目录
```

两个 PHP 服务将 **项目根目录的上一级** `../apps` 挂载到容器的 `/var/www/apps`，并共用 `php/conf.d` 中的配置。MariaDB 初始化脚本用于新数据目录的初始化；已有数据库不会因修改脚本而自动重新初始化。

Compose 声明了 `mysql-data`、`redis-data`、`woodpecker-data`、`dpanel-data`、`pgdata-data` 和 `tablespace` 命名卷。PostgreSQL 当前将 `pgdata-data` 挂载到 `/bitnami/postgresql`，而 `PGDATA` 设置为 `/var/lib/postgresql/data`；两者不一致，不能据此认为该命名卷保存了实际数据库数据。当前配置的初始化变量名也写为 `PPOSTGRES_INITDB_ARGS`。使用 PostgreSQL 保存重要数据前，应先核对并修正配置及迁移方案。

## 常用操作

```sh
docker compose ps
docker compose logs -f php83
docker compose restart redis
docker compose up -d --build php83
docker compose down
```

`docker compose down` 默认不会删除命名卷；不要在需要保留数据时使用 `down -v`。根目录 Makefile 的 `core-up`、`core-down`、`logs-core`、`up-all`、`down-all` 和 `ps` 对应根 Compose；其他分组目标引用独立的 `apps/.../docker-compose.yml`，需要自行提供对应文件。

PHP 和 Woodpecker 服务加入 `1panel-network`；PHP 另外加入 `pandora-net`。同一网络中的容器可通过 Compose 服务名访问相应服务。DPanel 和 Woodpecker Agent 挂载了 Docker socket，使用时应限制对这些服务的访问。Vaultwarden 当前允许注册，部署前请根据实际需要调整配置。

## 更新操作

docker-compose.yml
