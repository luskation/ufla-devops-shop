# Atividade 5 — A stack completa com Docker Compose

API, PostgreSQL, Redis e Nginx sobem juntos com `docker compose up -d --wait`, a API usa a
imagem publicada no GHCR, e os dados do banco sobrevivem a um `down` seguido de `up`
(volume nomeado `dados-banco`).

## (a) `docker compose ps` com tudo healthy

```text
$ docker compose ps
NAME                       IMAGE                               COMMAND                  SERVICE   CREATED          STATUS                    PORTS
ufla-devops-shop-api-1     ghcr.io/luskation/ufla-shop:1.0.0   "uvicorn app:api --h…"   api       29 seconds ago   Up 23 seconds (healthy)   8000/tcp
ufla-devops-shop-banco-1   postgres:16-alpine                  "docker-entrypoint.s…"   banco     29 seconds ago   Up 28 seconds (healthy)   5432/tcp
ufla-devops-shop-cache-1   redis:7-alpine                      "docker-entrypoint.s…"   cache     29 seconds ago   Up 28 seconds (healthy)   6379/tcp
ufla-devops-shop-nginx-1   nginx:1.27-alpine                   "/docker-entrypoint.…"   nginx     7 seconds ago    Up 5 seconds (healthy)    0.0.0.0:8090->80/tcp, [::]:8090->80/tcp
```

Só o `nginx` tem porta publicada; `api`, `banco` e `cache` só são acessíveis pela rede
interna do compose.

## (b) Roteiro de persistência

Executado a partir de um volume vazio (`docker compose down -v` antes de começar).

```text
$ docker compose up -d --wait
 ...
 Container ufla-devops-shop-cache-1 Healthy
 Container ufla-devops-shop-banco-1 Healthy
 Container ufla-devops-shop-api-1 Starting
 Container ufla-devops-shop-api-1 Started
 Container ufla-devops-shop-api-1 Waiting
 Container ufla-devops-shop-api-1 Healthy
 Container ufla-devops-shop-nginx-1 Starting
 ...
 Container ufla-devops-shop-nginx-1 Healthy

$ curl -I http://localhost
HTTP/1.1 200 OK

$ curl -s http://localhost/api/info
{"aplicacao":"ufla-devops-shop","versao":"1.0.0","banco":"postgresql","cache":"redis","instancia":"bcc0a2fa8585"}

$ curl -s -X POST http://localhost/api/produtos -H 'Content-Type: application/json' \
    -d '{"nome":"Prova de persistencia","preco":9.9,"estoque":1}'
{"id":13,"nome":"Prova de persistencia","descricao":"","preco":9.9,"estoque":1,"criado_em":"2026-10-27T22:40:39.065313+00:00"}

$ docker compose down
 Container ufla-devops-shop-nginx-1 Removed
 Container ufla-devops-shop-api-1 Removed
 Container ufla-devops-shop-cache-1 Removed
 Container ufla-devops-shop-banco-1 Removed
 Network ufla-devops-shop_default Removed

$ docker compose up -d --wait
 ...
 Container ufla-devops-shop-banco-1 Healthy
 Container ufla-devops-shop-cache-1 Healthy
 Container ufla-devops-shop-api-1 Healthy
 Container ufla-devops-shop-nginx-1 Healthy

$ curl -s 'http://localhost/api/busca?q=persistencia'
{"termo":"persistencia","total":1,"resultados":[{"id":13,"nome":"Prova de persistencia","descricao":"","preco":9.9,"estoque":1,"criado_em":"2026-10-27T22:40:39.065313+00:00"}]}
```

O `down` removeu os containers e a rede, mas não o volume `ufla-devops-shop_dados-banco`
(isso só aconteceria com `-v`). O PostgreSQL novo montou o mesmo volume e o produto 13
continuava lá, com o mesmo `criado_em`.

Note também a ordem no `up`: a `api` só começa (`Starting`) depois de `banco` e `cache`
estarem `Healthy`, e o `nginx` só depois da `api`.

## (c) Imagem no GHCR

`ghcr.io/luskation/ufla-shop:1.0.0`, pública:
https://github.com/users/luskation/packages/container/package/ufla-shop

```text
$ docker pull ghcr.io/luskation/ufla-shop:1.0.0     # sem docker login
ghcr.io/luskation/ufla-shop:1.0.0
```

## (d) Por que `depends_on` sozinho não resolve a ordem de subida?

O `depends_on` simples só garante que o container do banco foi **iniciado** antes do da
API, mas o PostgreSQL ainda leva alguns segundos para criar o banco e aceitar conexões, e
nesse intervalo a API sobe, tenta conectar e falha. Com `condition: service_healthy`, o
Compose espera o healthcheck do serviço (`pg_isready`, `redis-cli ping`) dar certo antes
de iniciar o dependente; ou seja, a dependência passa a ser "o banco está respondendo", e
não "o processo do banco existe".
