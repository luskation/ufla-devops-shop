# Atividade 3 — A aplicação como serviço Linux

A `ufla-devops-shop` roda como serviço do `systemd` (usuário não-root), com
PostgreSQL e Redis do sistema, backup diário com rotação e Nginx à frente
fazendo TLS.

| Artefato | Arquivo |
|----------|---------|
| Deploy idempotente | `scripts/deploy.sh` |
| Backup com rotação | `scripts/backup.sh` |
| Serviço e timer    | `systemd/ufla-shop.service`, `systemd/ufla-shop-backup.service`, `systemd/ufla-shop-backup.timer` |
| Proxy reverso TLS  | `nginx/loja.conf` |

## (a) Como rodar o `deploy.sh` numa máquina limpa

Pré-requisito: PostgreSQL e Redis instalados, com o usuário e o banco da
aplicação criados (o script não mexe no banco, que tem senha).

```bash
sudo apt install -y postgresql redis-server
sudo -u postgres psql -c "CREATE USER loja WITH PASSWORD 'sua-senha';"
sudo -u postgres psql -c "CREATE DATABASE loja OWNER loja;"

git clone https://github.com/luskation/ufla-devops-shop.git && cd ufla-devops-shop
sudo ./scripts/deploy.sh          # 1ª vez: cria /etc/ufla-shop.env a partir do exemplo
sudo nano /etc/ufla-shop.env      # troque "troque-esta-senha" pela senha do banco
sudo ./scripts/deploy.sh          # agora termina com "Aplicação no ar"
```

O script instala o que faltar (`python3-venv`, `rsync`, `curl`, `nginx`,
`openssl`), cria o usuário `ufla-shop`, sincroniza o código em
`/opt/ufla-shop`, cria o venv, instala as units e habilita o serviço e o timer,
gera o certificado autoassinado (se não existir), configura o Nginx e termina
consultando `/ready` até 10 vezes — `exit 1` se nunca receber 200.

A senha fica só em `/etc/ufla-shop.env` (`640 root:ufla-shop`), carregado pela
unit com `EnvironmentFile`; rodar o script de novo nunca sobrescreve esse
arquivo.

## (b) `systemctl status ufla-shop` depois do `kill -9`

```bash
sudo kill -9 $(systemctl show -p MainPID --value ufla-shop); sleep 5
systemctl status ufla-shop --no-pager
```

> `pidof uvicorn` não encontra o processo: o executável é o `python3` do venv,
> então o PID vem do próprio systemd.

```
● ufla-shop.service - ufla-devops-shop (API FastAPI)
     Loaded: loaded (/etc/systemd/system/ufla-shop.service; enabled; preset: enabled)
     Active: active (running) since Wed 2026-09-30 10:09:18 -03; 4s ago
   Main PID: 966668 (uvicorn)
      Tasks: 1 (limit: 34399)
     Memory: 42.0M (peak: 42.7M)
        CPU: 445ms
     CGroup: /system.slice/ufla-shop.service
             └─966668 /opt/ufla-shop/.venv/bin/python3 /opt/ufla-shop/.venv/bin/uvicorn app:api --host 127.0.0.1 --port 8000

set 30 10:09:18 lsk-notebook systemd[1]: ufla-shop.service: Scheduled restart job, restart counter is at 1.
set 30 10:09:18 lsk-notebook systemd[1]: Started ufla-shop.service - ufla-devops-shop (API FastAPI).
set 30 10:09:18 lsk-notebook uvicorn[966668]: INFO:     Started server process [966668]
set 30 10:09:18 lsk-notebook uvicorn[966668]: INFO:     Waiting for application startup.
set 30 10:09:18 lsk-notebook uvicorn[966668]: 2026-09-30 10:09:18,718 INFO loja: ufla-devops-shop 1.0.0 subindo (banco=postgresql, cache=redis, instancia=lsk-notebook)
set 30 10:09:18 lsk-notebook uvicorn[966668]: 2026-09-30 10:09:18,781 INFO loja.banco: banco pronto (modo postgresql)
set 30 10:09:18 lsk-notebook uvicorn[966668]: INFO:     Application startup complete.
set 30 10:09:18 lsk-notebook uvicorn[966668]: INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
```

`Scheduled restart job, restart counter is at 1`: o `Restart=on-failure`
subiu o serviço de novo sozinho.

## (c) `curl -kI https://localhost` e `curl -I http://localhost`

```
$ curl -kI https://localhost
HTTP/2 200
server: nginx/1.24.0 (Ubuntu)
date: Wed, 30 Sep 2026 13:09:53 GMT
content-type: text/html; charset=utf-8
content-length: 1262
accept-ranges: bytes
last-modified: Wed, 30 Sep 2026 12:43:44 GMT
etag: "108e2c1be706f6bd94eb4cae95c68a7e"
```

```
$ curl -I http://localhost
HTTP/1.1 301 Moved Permanently
Server: nginx/1.24.0 (Ubuntu)
Date: Wed, 30 Sep 2026 13:09:53 GMT
Content-Type: text/html
Content-Length: 178
Connection: keep-alive
Location: https://localhost/
```

A aplicação escuta só em `127.0.0.1:8000`; de fora, só o Nginx (80 e 443).

> A rota `/` só aceitava `GET`, e o `curl -I` manda `HEAD` — a resposta era
> `405`. Ela passou a aceitar `GET` e `HEAD` (`app/principal.py`).

## (d) `ls -la /var/backups/ufla-shop` depois de três backups

```bash
for i in 1 2 3; do sudo /opt/ufla-shop/scripts/backup.sh; [ $i -lt 3 ] && sleep 61; done
sudo ls -la /var/backups/ufla-shop
```

```
backup gerado: /var/backups/ufla-shop/loja-2026-09-30-1007.sql.gz (4,0K)
backup gerado: /var/backups/ufla-shop/loja-2026-09-30-1008.sql.gz (4,0K)
backup gerado: /var/backups/ufla-shop/loja-2026-09-30-1009.sql.gz (4,0K)
total 24
drwx------ 2 root root 4096 set 30 10:09 .
drwxr-xr-x 3 root root 4096 set 30 10:04 ..
-rw------- 1 root root 1591 set 30 10:04 loja-2026-09-30-1004.sql.gz
-rw------- 1 root root 1591 set 30 10:07 loja-2026-09-30-1007.sql.gz
-rw------- 1 root root 1591 set 30 10:08 loja-2026-09-30-1008.sql.gz
-rw------- 1 root root 1593 set 30 10:09 loja-2026-09-30-1009.sql.gz
```

O nome tem precisão de minuto, por isso o intervalo de 61 s entre as
execuções. O `loja-...-1004` é de um teste anterior. Cada execução registra
uma linha no journal (`journalctl -t backup`); a rotação mantém os 7 mais
recentes. O dump é gravado num temporário e só renomeado no fim, e o
`pipefail` faz uma falha do `pg_dump` derrubar o `pg_dump | gzip` — um backup
que falhou nunca aparece aqui.

O timer roda o mesmo script todo dia às 3h:

```
$ systemctl list-timers ufla-shop-backup.timer
NEXT                        LEFT LAST PASSED UNIT                   ACTIVATES
Thu 2026-10-01 03:00:00 -03  16h -         - ufla-shop-backup.timer ufla-shop-backup.service
```

## (e) Idempotência: duas execuções seguidas do `deploy.sh`

1ª execução:

```
==> Usuário ufla-shop já existe
==> Sincronizando código em /opt/ufla-shop
==> Instalando requirements.txt
==> Instalando units do systemd
==> Instalando configuração do Nginx
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
Synchronizing state of nginx.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable nginx
==> Aguardando http://localhost:8000/ready
==> Aplicação no ar (tentativa 1)
```

2ª execução, logo em seguida:

```
==> Usuário ufla-shop já existe
==> Sincronizando código em /opt/ufla-shop
==> Instalando requirements.txt
==> Instalando units do systemd
==> Instalando configuração do Nginx
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
Synchronizing state of nginx.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install enable nginx
==> Aguardando http://localhost:8000/ready
==> Aplicação no ar (tentativa 1)
```

Saídas idênticas: o usuário não é recriado, o venv não é recriado, o
certificado não é regerado, `/etc/ufla-shop.env` não é sobrescrito, e as duas
terminam com o `/ready` respondendo 200.
