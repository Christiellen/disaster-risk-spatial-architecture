#!/usr/bin/env bash
# Carrega a amostra sintética completa (território, ocorrências v1 e v2, áreas de risco).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m etl.carregar_ibge --amostra \
    --municipios data/sample/ibge_municipios_amostra.json \
    --malha-uf data/sample/ibge_malha_uf_amostra.json \
    --malha-mun data/sample/ibge_malha_mun_amostra.json
python3 -m etl.carregar_atlas --fonte AMOSTRA --arquivo data/sample/atlas_amostra_v1.csv
python3 -m etl.carregar_atlas --fonte AMOSTRA --arquivo data/sample/atlas_amostra_v1.csv   # idempotência: deve ser ignorado
python3 -m etl.carregar_areas_risco --amostra --arquivo data/sample/areas_risco_amostra.geojson \
    --fonte SGB_SETORIZACAO_AMOSTRA --campo-id ID_SETOR --campo-grau GRAU \
    --campo-tipologia TIPOLOGIA --campo-municipio GEOCODIGO --campo-cobrade COBRADE
python3 -m etl.carregar_atlas --fonte AMOSTRA --arquivo data/sample/atlas_amostra_v2.csv
