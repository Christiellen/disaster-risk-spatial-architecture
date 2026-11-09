"""Carga de setores de risco a partir de GeoJSON (ex.: setorização do SGB exportada em GeoJSON).

Como os nomes de atributos variam entre fontes, informe quais propriedades usar:

    python -m etl.carregar_areas_risco --arquivo setores.geojson --fonte SGB_SETORIZACAO \
        --campo-id ID_SETOR --campo-grau GRAU_RISCO --campo-tipologia TIPOLOGIA \
        [--campo-municipio GEOCODIGO] [--campo-cobrade COBRADE] [--campo-data DATA]

Sem --campo-municipio, o município é inferido pela maior interseção com a malha.
Shapefile? Converta antes:  ogr2ogr -f GeoJSON -t_srs EPSG:4674 setores.geojson setores.shp
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from etl.comum import abrir_lote, conectar, imprimir_resultado


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--arquivo", required=True, type=Path)
    p.add_argument("--fonte", required=True, help="Nome da fonte gravado em risco.area_risco.fonte")
    p.add_argument("--campo-id", required=True)
    p.add_argument("--campo-grau", required=True)
    p.add_argument("--campo-tipologia", required=True)
    p.add_argument("--campo-municipio")
    p.add_argument("--campo-cobrade")
    p.add_argument("--campo-data")
    p.add_argument("--amostra", action="store_true")
    args = p.parse_args()

    dados = json.loads(args.arquivo.read_text(encoding="utf-8"))
    lote_fonte = "AMOSTRA" if args.amostra else "SGB_AREAS_RISCO"

    def prop(props: dict, campo: str | None):
        valor = props.get(campo) if campo else None
        return None if valor is None else str(valor)

    with conectar() as conn:
        id_lote = abrir_lote(conn, lote_fonte, args.arquivo)
        if id_lote is None:
            print(f"{args.arquivo.name} já carregado.")
            return
        with conn.cursor().copy(
            "COPY staging.area_risco (id_lote, linha_origem, fonte, id_externo, cd_mun, tipologia, "
            "grau_risco, cobrade, dt_referencia, geojson) FROM STDIN"
        ) as copy:
            for i, f in enumerate(dados.get("features", []), start=1):
                props = f.get("properties") or {}
                copy.write_row([
                    id_lote, i, args.fonte,
                    prop(props, args.campo_id), prop(props, args.campo_municipio),
                    prop(props, args.campo_tipologia), prop(props, args.campo_grau),
                    prop(props, args.campo_cobrade), prop(props, args.campo_data),
                    json.dumps(f.get("geometry")),
                ])
        resultado = conn.execute("SELECT * FROM risco.fn_processar_lote_areas_risco(%s)", (id_lote,)).fetchone()
        imprimir_resultado("areas-risco", id_lote, resultado, conn)
        conn.commit()


if __name__ == "__main__":
    main()
