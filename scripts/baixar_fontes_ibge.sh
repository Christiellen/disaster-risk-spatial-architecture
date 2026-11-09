#!/usr/bin/env bash
# Baixa o cadastro e as malhas de municípios e UFs das APIs públicas do IBGE.
# O Atlas Digital de Desastres é baixado manualmente (ver README, seção "Dados reais").
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/raw/ibge

BASE="https://servicodados.ibge.gov.br/api"
QUALIDADE="${QUALIDADE:-intermediaria}"   # minima | intermediaria | maxima

echo "Cadastro de municípios..."
curl -fsSL "$BASE/v1/localidades/municipios?view=nivelado" -o data/raw/ibge/municipios.json

echo "Malha municipal (qualidade $QUALIDADE)..."
curl -fsSL "$BASE/v3/malhas/paises/BR?formato=application/vnd.geo%2Bjson&intrarregiao=municipio&qualidade=$QUALIDADE" \
     -o data/raw/ibge/malha_municipios.json

echo "Malha das UFs..."
curl -fsSL "$BASE/v3/malhas/paises/BR?formato=application/vnd.geo%2Bjson&intrarregiao=UF&qualidade=$QUALIDADE" \
     -o data/raw/ibge/malha_ufs.json

ls -lh data/raw/ibge
