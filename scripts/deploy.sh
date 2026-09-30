#!/usr/bin/env bash
#
# deploy.sh -- DevOps na Prática (DCC/UFLA), Atividade 3
#
# Instala (ou atualiza) a ufla-devops-shop como serviço do systemd.
# Idempotente: rodar de novo sincroniza o código, reinstala o que mudou e
# reinicia o serviço -- sem duplicar usuário, venv, units ou configuração.
#
#   Uso:  sudo ./scripts/deploy.sh
#
#   Código de saída:  0 = aplicação no ar e /ready respondendo 200
#                     1 = algo falhou (inclusive o healthcheck final)
#
# Pré-requisito: PostgreSQL e Redis rodando, com o usuário e o banco da
# aplicação criados (Parte 1.1). A senha do banco NÃO fica aqui: fica em
# /etc/ufla-shop.env, carregado pela unit com EnvironmentFile.
#
# ---------------------------------------------------------------------------
set -euo pipefail

APP_USER=ufla-shop
APP_DIR=/opt/ufla-shop
SERVICO=ufla-shop.service
ENV_FILE=/etc/ufla-shop.env
ENV_EXEMPLO=/etc/ufla-shop.env.example
SSL_DIR=/etc/nginx/ssl
URL_READY=http://localhost:8000/ready

# Raiz do repositório, de onde quer que o script seja chamado.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '==> %s\n' "$*"; }

if [ "$EUID" -ne 0 ]; then
    echo "Rode como root: sudo $0" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 0. Pacotes do sistema necessários para o próprio deploy.
#    Só chama o gerenciador de pacotes se falta alguma coisa.
# ---------------------------------------------------------------------------
if ! /usr/bin/python3 -c 'import ensurepip' 2>/dev/null \
    || ! command -v rsync >/dev/null || ! command -v curl >/dev/null \
    || ! command -v nginx >/dev/null || ! command -v openssl >/dev/null; then
    log "Instalando python3-venv, rsync, curl, nginx e openssl"
    if command -v apt-get >/dev/null; then
        apt-get install -y python3-venv rsync curl nginx openssl
    else
        dnf install -y python3 rsync curl nginx openssl
    fi
fi

# ---------------------------------------------------------------------------
# 1. Usuário de sistema: sem shell de login e sem home.
# ---------------------------------------------------------------------------
if id "$APP_USER" >/dev/null 2>&1; then
    log "Usuário $APP_USER já existe"
else
    log "Criando usuário de sistema $APP_USER"
    useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
fi

# ---------------------------------------------------------------------------
# 2. Código em /opt/ufla-shop. O rsync --delete remove o que saiu do
#    repositório; o venv fica de fora da sincronização para não ser apagado.
# ---------------------------------------------------------------------------
log "Sincronizando código em $APP_DIR"
install -d -m 755 "$APP_DIR"
rsync -a --delete \
    --exclude '.venv/' \
    "$REPO/app" "$REPO/static" "$REPO/requirements.txt" \
    "$APP_DIR/"
install -D -m 755 "$REPO/scripts/backup.sh" "$APP_DIR/scripts/backup.sh"

if [ ! -x "$APP_DIR/.venv/bin/python" ]; then
    log "Criando venv"
    /usr/bin/python3 -m venv "$APP_DIR/.venv"
fi
log "Instalando requirements.txt"
"$APP_DIR/.venv/bin/pip" install --quiet --disable-pip-version-check \
    -r "$APP_DIR/requirements.txt"

# ---------------------------------------------------------------------------
# 3. Configuração com segredos. O exemplo é sempre atualizado; o arquivo real
#    só é criado se não existir -- rodar de novo nunca sobrescreve a senha.
# ---------------------------------------------------------------------------
install -m 644 "$REPO/systemd/ufla-shop.env.example" "$ENV_EXEMPLO"
if [ ! -f "$ENV_FILE" ]; then
    log "Criando $ENV_FILE a partir do exemplo -- EDITE a senha do banco"
    install -m 640 -o root -g "$APP_USER" "$ENV_EXEMPLO" "$ENV_FILE"
fi

# ---------------------------------------------------------------------------
# 4. Units do systemd: a API e o timer do backup.
# ---------------------------------------------------------------------------
log "Instalando units do systemd"
install -m 644 "$REPO"/systemd/*.service "$REPO"/systemd/*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable "$SERVICO"
systemctl restart "$SERVICO"
systemctl enable --now ufla-shop-backup.timer

# ---------------------------------------------------------------------------
# 5. Nginx com TLS. O certificado autoassinado só é gerado se não existir
#    (e não vai para o repositório: *.pem e *.key estão no .gitignore).
# ---------------------------------------------------------------------------
if [ ! -f "$SSL_DIR/loja.pem" ] || [ ! -f "$SSL_DIR/loja.key" ]; then
    log "Gerando certificado autoassinado em $SSL_DIR"
    install -d -m 755 "$SSL_DIR"
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
        -keyout "$SSL_DIR/loja.key" -out "$SSL_DIR/loja.pem" \
        -subj "/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
    chmod 600 "$SSL_DIR/loja.key"
fi

log "Instalando configuração do Nginx"
if [ -d /etc/nginx/sites-available ]; then
    # Debian/Ubuntu: o site "default" também escuta na 80 e disputaria com o nosso.
    install -m 644 "$REPO/nginx/loja.conf" /etc/nginx/sites-available/loja.conf
    ln -sfn /etc/nginx/sites-available/loja.conf /etc/nginx/sites-enabled/loja.conf
    rm -f /etc/nginx/sites-enabled/default
else
    install -m 644 "$REPO/nginx/loja.conf" /etc/nginx/conf.d/loja.conf
fi
nginx -t
systemctl enable nginx
systemctl reload-or-restart nginx

# ---------------------------------------------------------------------------
# 6. Healthcheck: /ready só devolve 200 se banco E cache respondem.
# ---------------------------------------------------------------------------
log "Aguardando $URL_READY"
for tentativa in $(seq 1 10); do
    codigo=$(curl -s -o /dev/null -w '%{http_code}' "$URL_READY" || true)
    if [ "$codigo" = "200" ]; then
        log "Aplicação no ar (tentativa $tentativa)"
        exit 0
    fi
    sleep 1
done

echo "FALHA: $URL_READY não respondeu 200 em 10 tentativas (último código: $codigo)" >&2
echo "Veja: journalctl -u $SERVICO -n 50 --no-pager" >&2
exit 1
