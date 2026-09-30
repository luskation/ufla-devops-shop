#!/usr/bin/env bash
#
# backup.sh -- DevOps na Prática (DCC/UFLA), Atividade 3
#
# pg_dump do banco da aplicação, comprimido, com rotação dos 7 mais recentes.
# Executado diariamente pelo ufla-shop-backup.timer, mas pode rodar à mão:
#
#   Uso:  sudo /opt/ufla-shop/scripts/backup.sh
#
#   Código de saída:  0 = dump gerado
#                     != 0 = falhou (e nenhum arquivo pela metade fica para trás)
#
# A conexão vem de DATABASE_URL, que a unit carrega de /etc/ufla-shop.env.
#
# ---------------------------------------------------------------------------
# pipefail é o que faz uma falha do pg_dump em 'pg_dump | gzip' derrubar o
# script: sem ele, o código de saída do pipe seria só o do gzip (sucesso).
set -euo pipefail

DESTINO=/var/backups/ufla-shop
MANTER=7
ENV_FILE=/etc/ufla-shop.env

# Rodando à mão, fora da unit, a variável não vem do EnvironmentFile.
if [ -z "${DATABASE_URL:-}" ] && [ -r "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    . "$ENV_FILE"
fi
: "${DATABASE_URL:?DATABASE_URL não definida (veja $ENV_FILE)}"

install -d -m 700 "$DESTINO"
ARQUIVO="$DESTINO/loja-$(date +%Y-%m-%d-%H%M).sql.gz"

# Grava num temporário e só renomeia no fim: um dump que falhou no meio nunca
# vira um loja-*.sql.gz e, portanto, nunca empurra um backup bom para fora
# da rotação.
TEMP="$(mktemp "$DESTINO/.loja-XXXXXX.sql.gz")"
trap 'rm -f "$TEMP"; logger -t backup -p user.err "FALHA no backup do banco loja"' ERR

pg_dump --no-owner "$DATABASE_URL" | gzip > "$TEMP"
chmod 600 "$TEMP"
mv "$TEMP" "$ARQUIVO"
trap - ERR

TAMANHO="$(du -h "$ARQUIVO" | cut -f1)"
logger -t backup "backup gerado: $ARQUIVO ($TAMANHO)"
echo "backup gerado: $ARQUIVO ($TAMANHO)"

# Rotação: o nome tem a data em ordem ano-mês-dia-horaminuto, então ordem
# alfabética reversa é do mais novo para o mais velho.
find "$DESTINO" -maxdepth 1 -name 'loja-*.sql.gz' -printf '%f\n' \
    | sort -r \
    | tail -n +$((MANTER + 1)) \
    | while read -r antigo; do
        rm -f -- "$DESTINO/$antigo"
        echo "removido: $antigo"
    done
