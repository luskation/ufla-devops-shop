# Atividade 4 — A aplicação em container

Imagem final: `ufla-shop:1.0`, **117 MB** (`docker image inspect --format '{{.Size}}'`),
multi-stage com estágio final `python:3.12-alpine`, usuário não-root, `HEALTHCHECK` em
`/health` e `docker stop` em ~0,4 s.

> Medido com Docker 29.8.1 (containerd image store), amd64. Nesse store o
> `docker images` mostra duas colunas: `DISK USAGE` (o que a correção lê via
> `.Size`) e `CONTENT SIZE` (camadas comprimidas). Por isso os valores
> absolutos não batem com a tabela de `docs/aplicacao.md`; o que importa é a
> comparação entre as versões, todas medidas da mesma forma.

## 1. Primeira versão × versão final

Primeira versão que funcionou (`FROM python:3.12-slim`, `COPY . .`, `pip install`, sem
`.dockerignore`):

```text
IMAGE           ID             DISK USAGE   CONTENT SIZE
ufla-shop:0.1   fd131cd08218        512MB          111MB
ufla-shop:1.0   8af08e3fa2a9        117MB         26.8MB
```

| Versão | Base | `.Size` |
|--------|------|---------|
| 0.1 — primeira que funcionou | `python:3.12-slim` | **513 MB** |
| 1.0 — final | `python:3.12-alpine` (multi-stage) | **117 MB** |

## 2. O que mudou e quanto cada mudança economizou

Cada passo foi construído e medido separadamente:

| Passo | Mudança | `.Size` | Economia |
|-------|---------|---------|----------|
| 0.1 | slim, `COPY . .`, sem `.dockerignore` | 513 MB | — |
| 0.2 | + `.dockerignore` | 275 MB | **−238 MB** |
| 0.3 | + multi-stage, venv sem `pip`/`__pycache__`, `COPY` só de `app/` e `static/` | 223 MB | **−52 MB** |
| 1.0 | estágio final em `python:3.12-alpine` | 117 MB | **−106 MB** |

**`.dockerignore` (−238 MB).** No `docker history` da 0.1 a camada `COPY . .` tinha
199 MB: o `.venv` local, o `.git`, `loja.db`, caches e os dados das atividades
anteriores. Com o `.dockerignore` essa camada caiu para 74 kB. Além do tamanho, isso
evita vazar `.env` e `.git` para dentro da imagem.

**Multi-stage (−52 MB).** O `pip install` roda no estágio `build`, dentro de um venv em
`/opt/venv`, com `--no-cache-dir` e `--no-compile`; depois o próprio `pip` é removido do
venv e os `__pycache__` são apagados. O estágio final recebe só esse venv (35 MB na
camada) e só os diretórios `app/` e `static/` — nada de `tests/`, `docs/`, `scripts/`
ou `requirements-dev.txt`.

**Alpine (−106 MB).** Só a base slim já ocupa a maior parte da imagem (Debian + glibc +
utilitários). A base Alpine (musl + busybox) é bem menor, e todas as dependências,
inclusive o `psycopg[binary]`, têm wheels para musl, então nada precisa ser compilado.
Bônus: o `wget` do busybox já vem na base e serve para o `HEALTHCHECK` sem instalar
`curl`.

O que **não** funcionou: rodar `pip uninstall pip` no estágio final. Apagar arquivos
de uma camada da imagem base numa camada nova não diminui a imagem; essa camada
*acrescentou* 242 kB (os arquivos de remoção). Por isso a limpeza fica toda no estágio
`build`, antes do `COPY --from`.

Outras decisões do `Dockerfile`:

- **Não-root:** usuário de sistema `loja`; o código fica com o dono root (só leitura
  para o processo) e só `/dados` é gravável, onde o SQLite fica (`SQLITE_PATH=/dados/loja.db`).
- **`CMD` na forma exec:** o `uvicorn` é o PID 1 e recebe o `SIGTERM` direto do
  `docker stop`. Na forma shell (`CMD uvicorn ...`), o PID 1 seria o `/bin/sh`, que não
  repassa o sinal, e o Docker só mataria o processo com `SIGKILL` após 10 s.
- `PYTHONDONTWRITEBYTECODE=1` (não tenta gravar `.pyc` num código que o usuário não pode
  escrever) e `PYTHONUNBUFFERED=1` (logs aparecem na hora no `docker logs`).

## 3. Saída da verificação

A porta 8000 do host já está ocupada pelo serviço systemd da Atividade 3, por isso
publiquei em `-p 8080:8000`. O container continua escutando na 8000.

```text
$ docker image inspect --format '{{.Size}}' ufla-shop:1.0 | numfmt --to=si
117M

$ docker run -d --name loja -p 8080:8000 ufla-shop:1.0
b2d1fc4c82d9368b1d489e867c542f0c9133c32d26ddc00854fa8d98eda8a7a2

$ docker run --rm ufla-shop:1.0 id -u
100

$ docker run --rm ufla-shop:1.0 ls -a
.
..
app
static

$ sleep 10 && docker inspect --format '{{.State.Health.Status}}' loja
healthy

$ curl -s localhost:8080/health && curl -s localhost:8080/api/produtos | head -c 200
{"status":"ok","versao":"1.0.0"}[{"id":1,"nome":"Caneca DevOps na Prática","descricao":"Cerâmica, 350 ml: 'funciona na minha máquina'","preco":39.9,"estoque":25,"criado_em":"2026-10-27 22:21:27"},{"id":2,"nome":"Camiseta UFLA Com

$ curl -s localhost:8080/api/produtos | python3 -c 'import sys,json;print(len(json.load(sys.stdin)),"produtos")'
12 produtos

$ time docker stop loja
loja

real	0m0,428s
user	0m0,017s
sys	0m0,024s
```

## 4. Por que o `HEALTHCHECK` consulta `/health` e não `/ready`?

O `/health` responde só se o processo está de pé, enquanto o `/ready` depende do banco e
do cache: se o `HEALTHCHECK` usasse o `/ready`, uma queda do PostgreSQL ou do Redis
marcaria como `unhealthy` (e um orquestrador reiniciaria) um container que está
perfeitamente saudável, e reiniciá-lo não conserta a dependência. A pergunta "devo
reiniciar este processo?" é de liveness (`/health`); "devo mandar tráfego para ele?" é
de readiness (`/ready`), e quem usa essa resposta é o balanceador/Kubernetes, não o
`HEALTHCHECK`.
