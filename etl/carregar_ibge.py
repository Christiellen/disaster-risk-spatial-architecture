"""Carga do território a partir das APIs públicas do IBGE.

Arquivos esperados (baixados por scripts/baixar_fontes_ibge.sh):
    municipios.json      API de Localidades, ?view=nivelado
    malha_municipios.json API de Malhas v3, intrarregiao=municipio (GeoJSON)
    malha_ufs.json       API de Malhas v3, intrarregiao=UF (GeoJSON)

Uso:
    python -m etl.carregar_ibge --municipios data/raw/ibge/municipios.json \
        --malha-mun data/raw/ibge/malha_municipios.json --malha-uf data/raw/ibge/malha_ufs.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from etl.comum import abrir_lote, conectar, imprimir_resultado


def _linha_municipio(reg: dict) -> list:
    """Aceita a visão nivelada ('UF-sigla') e, como alternativa, a aninhada
    (regiao-imediata > regiao-intermediaria > UF)."""
    if "municipio-id" in reg:
        return [reg.get("municipio-id"), reg.get("municipio-nome"), reg.get("UF-id"),
                reg.get("UF-sigla"), reg.get("UF-nome"), reg.get("regiao-sigla")]
    uf = (((reg.get("regiao-imediata") or {}).get("regiao-intermediaria") or {}).get("UF")
          or ((reg.get("microrregiao") or {}).get("mesorregiao") or {}).get("UF") or {})
    return [reg.get("id"), reg.get("nome"), uf.get("id"), uf.get("sigla"), uf.get("nome"),
            (uf.get("regiao") or {}).get("sigla")]


def carregar_municipios(arquivo: Path, fonte: str) -> None:
    dados = json.loads(arquivo.read_text(encoding="utf-8"))
    with conectar() as conn:
        id_lote = abrir_lote(conn, fonte, arquivo)
        if id_lote is None:
            print(f"{arquivo.name} já carregado.")
            return
        with conn.cursor().copy(
            "COPY staging.ibge_municipio (id_lote, linha_origem, cd_mun, nome_mun, cd_uf, sigla_uf, nome_uf, sigla_regiao) FROM STDIN"
        ) as copy:
            for i, reg in enumerate(dados, start=1):
                valores = [None if v is None else str(v) for v in _linha_municipio(reg)]
                copy.write_row([id_lote, i, *valores])
        resultado = conn.execute("SELECT * FROM core.fn_processar_lote_ibge_municipios(%s)", (id_lote,)).fetchone()
        imprimir_resultado("ibge-municipios", id_lote, resultado, conn)
        conn.commit()


def carregar_malha(arquivo: Path, nivel: str, fonte: str) -> None:
    dados = json.loads(arquivo.read_text(encoding="utf-8"))
    with conectar() as conn:
        id_lote = abrir_lote(conn, fonte, arquivo)
        if id_lote is None:
            print(f"{arquivo.name} já carregado.")
            return
        with conn.cursor().copy(
            "COPY staging.ibge_malha (id_lote, linha_origem, nivel, codarea, geojson) FROM STDIN"
        ) as copy:
            for i, feicao in enumerate(dados.get("features", []), start=1):
                props = feicao.get("properties") or {}
                codigo = props.get("codarea") or props.get("CD_MUN") or props.get("cd_mun") or props.get("CD_UF")
                copy.write_row([id_lote, i, nivel, str(codigo) if codigo is not None else None,
                                json.dumps(feicao.get("geometry"))])
        resultado = conn.execute("SELECT * FROM core.fn_processar_lote_ibge_malha(%s)", (id_lote,)).fetchone()
        imprimir_resultado(f"ibge-malha-{nivel.lower()}", id_lote, resultado, conn)
        conn.commit()


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--municipios", type=Path)
    p.add_argument("--malha-mun", type=Path)
    p.add_argument("--malha-uf", type=Path)
    p.add_argument("--amostra", action="store_true", help="Registra os lotes com fonte AMOSTRA.")
    args = p.parse_args()

    if args.municipios:
        carregar_municipios(args.municipios, "AMOSTRA" if args.amostra else "IBGE_MUNICIPIOS")
    if args.malha_uf:
        carregar_malha(args.malha_uf, "UF", "AMOSTRA" if args.amostra else "IBGE_MALHA_UF")
    if args.malha_mun:
        carregar_malha(args.malha_mun, "MUN", "AMOSTRA" if args.amostra else "IBGE_MALHA_MUN")


if __name__ == "__main__":
    main()
