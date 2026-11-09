#!/usr/bin/env bash
# Aplica as migrações em ordem de versão usando apenas psql.
# Uso preferencial é o Flyway (docker compose up). Este script existe
# para a CI e para ambientes sem Flyway. Registra o que já foi aplicado
# em public.migracao_aplicada, então pode ser executado várias vezes.
set -euo pipefail

DIR="$(cd "$(dirname "$0")/../db/migrations" && pwd)"
PSQL=(psql -v ON_ERROR_STOP=1 -X -q)

"${PSQL[@]}" -c "CREATE TABLE IF NOT EXISTS public.migracao_aplicada (
    versao integer PRIMARY KEY, arquivo text NOT NULL, aplicada_em timestamptz NOT NULL DEFAULT now());"

for arquivo in $(ls "$DIR" | grep -E '^V[0-9]+__.*\.sql$' | sort -t_ -k1.2 -n); do
    versao="$(echo "$arquivo" | sed -E 's/^V([0-9]+)__.*/\1/')"
    ja_aplicada="$("${PSQL[@]}" -tAc "SELECT 1 FROM public.migracao_aplicada WHERE versao = $versao")"
    if [[ -z "$ja_aplicada" ]]; then
        echo "Aplicando $arquivo"
        "${PSQL[@]}" --single-transaction \
            -f "$DIR/$arquivo" \
            -c "INSERT INTO public.migracao_aplicada (versao, arquivo) VALUES ($versao, '$arquivo')"
    fi
done
echo "Migrações em dia."
