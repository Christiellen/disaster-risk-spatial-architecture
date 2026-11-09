"""Valida as respostas reais do banco contra os JSON Schemas de contracts/.

Garante que o que o banco entrega é o que o contrato promete: se uma
migração quebrar o contrato, este teste falha na CI.
"""

import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

from etl.comum import conectar

PASTA = Path(__file__).resolve().parent.parent / "contracts"


def carregar(nome: str) -> dict:
    return json.loads((PASTA / nome).read_text(encoding="utf-8"))


def main() -> None:
    oc, sync = carregar("ocorrencia.v1.schema.json"), carregar("sincronizacao.v1.schema.json")
    registro = Registry().with_resources([
        ("ocorrencia.v1.schema.json", Resource.from_contents(oc)),
        (oc["$id"], Resource.from_contents(oc)),
    ])
    v_oc = Draft202012Validator(oc, registry=registro, format_checker=FormatChecker())
    v_sync = Draft202012Validator({**sync, "$id": "sincronizacao.v1.schema.json"}, registry=registro,
                                  format_checker=FormatChecker())

    erros: list[str] = []
    with conectar() as conn:
        linhas = conn.execute("SELECT to_jsonb(v) FROM api.v1_ocorrencia v").fetchall()
        for (registro_json,) in linhas:
            erros += [f"ocorrencia {registro_json['id']}: {e.message}" for e in v_oc.iter_errors(registro_json)]

        geo = conn.execute("SELECT api.fn_v1_ocorrencias_geojson()").fetchone()[0]
        for f in geo["features"]:
            erros += [f"geojson {f['id']}: {e.message}"
                      for e in v_oc.iter_errors({**f["properties"],
                                                 "longitude": f["geometry"]["coordinates"][0],
                                                 "latitude": f["geometry"]["coordinates"][1]})]

        pagina = conn.execute("SELECT api.fn_v1_sincronizar(0, 5000)").fetchone()[0]
        erros += [f"sincronizacao: {e.message}" for e in v_sync.iter_errors(pagina)]

    if erros:
        raise SystemExit("Contrato violado:\n  " + "\n  ".join(erros))
    print(f"070 contrato: {len(linhas)} ocorrências, {len(geo['features'])} feições e 1 página de sincronização válidas")


if __name__ == "__main__":
    main()
