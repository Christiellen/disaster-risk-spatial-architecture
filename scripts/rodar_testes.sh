#!/usr/bin/env bash
# Recria o banco de teste do zero, aplica migrações, carrega a amostra e
# executa todos os testes. Usa as variáveis do libpq (PGHOST, PGPORT, PGUSER).
#
# ATENÇÃO: apaga e recria o banco indicado em PGDATABASE_TESTE
# (padrão: s2id_teste). Nunca aponte para um banco com dados reais.
set -euo pipefail
cd "$(dirname "$0")/.."

BANCO="${PGDATABASE_TESTE:-s2id_teste}"
if [[ "$BANCO" != *teste* && "$BANCO" != *test* ]]; then
    echo "Recusado: o nome do banco de teste precisa conter 'teste' ou 'test' (recebido: $BANCO)." >&2
    exit 1
fi

psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $BANCO WITH (FORCE)" -c "CREATE DATABASE $BANCO"
export PGDATABASE="$BANCO"

./scripts/aplicar_migracoes.sh
./scripts/carregar_amostra.sh

for teste in tests/sql/*.sql; do
    psql -X -q -v ON_ERROR_STOP=1 -f "$teste"
done
python3 -m tests.validar_contrato

echo "Todos os testes passaram."
