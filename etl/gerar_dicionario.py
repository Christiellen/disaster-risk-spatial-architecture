"""Gera docs/05-dicionario-de-dados.md a partir do catálogo do PostgreSQL.

O dicionário nunca é escrito à mão: os COMMENT ON das migrações são a
fonte, e o teste 010 garante que nenhuma tabela ou coluna fique sem
descrição. Assim documentação e implementação não divergem.

Uso:  python -m etl.gerar_dicionario [--saida docs/05-dicionario-de-dados.md]
"""

from __future__ import annotations

import argparse
from pathlib import Path

from etl.comum import conectar

SCHEMAS = ["core", "risco", "controle", "staging", "hist", "api", "analitico"]

SQL_OBJETOS = """
SELECT n.nspname, c.relname,
       CASE c.relkind WHEN 'r' THEN 'Tabela' WHEN 'v' THEN 'Visão' WHEN 'm' THEN 'Visão materializada' END,
       coalesce(obj_description(c.oid, 'pg_class'), '')
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = ANY(%s) AND c.relkind IN ('r', 'v', 'm')
ORDER BY array_position(%s::text[], n.nspname::text), c.relname
"""

SQL_COLUNAS = """
SELECT a.attname,
       format_type(a.atttypid, a.atttypmod),
       CASE WHEN a.attnotnull THEN 'sim' ELSE 'não' END,
       coalesce(
         (SELECT string_agg(DISTINCT CASE k.contype WHEN 'p' THEN 'PK' WHEN 'u' THEN 'UK'
                                     WHEN 'f' THEN 'FK → ' || k.confrelid::regclass END, ', ')
          FROM pg_constraint k WHERE k.conrelid = c.oid AND a.attnum = ANY (k.conkey) AND k.contype IN ('p','u','f')),
         ''),
       CASE WHEN a.attgenerated = 's' THEN 'gerada'
            WHEN a.attidentity <> '' THEN 'identity'
            ELSE coalesce(pg_get_expr(d.adbin, d.adrelid), '') END,
       coalesce(col_description(c.oid, a.attnum), '')
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum AND a.attgenerated = ''
WHERE n.nspname = %s AND c.relname = %s
ORDER BY a.attnum
"""

SQL_CHECKS = """
SELECT k.conname, pg_get_constraintdef(k.oid)
FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = %s AND c.relname = %s AND k.contype = 'c'
ORDER BY k.conname
"""

SQL_INDICES = """
SELECT ic.relname, am.amname, pg_get_indexdef(i.indexrelid)
FROM pg_index i
JOIN pg_class ic ON ic.oid = i.indexrelid JOIN pg_am am ON am.oid = ic.relam
JOIN pg_class c ON c.oid = i.indrelid JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = %s AND c.relname = %s AND NOT i.indisprimary
ORDER BY ic.relname
"""


def esc(texto: str) -> str:
    return texto.replace("|", "\\|").replace("\n", " ")


def gerar() -> str:
    saida = ["# Dicionário de dados", "",
             "> Gerado automaticamente por `python -m etl.gerar_dicionario` a partir do catálogo do banco.",
             "> Não edite à mão: altere o `COMMENT ON` na migração e regenere.", ""]
    with conectar() as conn:
        objetos = conn.execute(SQL_OBJETOS, (SCHEMAS, SCHEMAS)).fetchall()
        saida.append("## Sumário\n")
        schema_atual = None
        for schema, nome, tipo, desc in objetos:
            if schema != schema_atual:
                saida.append(f"\n**{schema}**\n")
                schema_atual = schema
            saida.append(f"- [`{schema}.{nome}`](#{schema}{nome}) - {tipo.lower()}: {esc(desc)[:110]}")
        saida.append("")

        for schema, nome, tipo, desc in objetos:
            saida += [f"## {schema}.{nome}", "", f"*{tipo}.* {esc(desc)}", "",
                      "| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |",
                      "|---|---|---|---|---|---|"]
            for col, tipo_col, obrig, chave, padrao, desc_col in conn.execute(SQL_COLUNAS, (schema, nome)):
                saida.append(f"| `{col}` | {tipo_col} | {obrig} | {chave} | {esc(padrao)[:40]} | {esc(desc_col)} |")
            checks = conn.execute(SQL_CHECKS, (schema, nome)).fetchall()
            if checks:
                saida += ["", "**Regras (CHECK)**", ""]
                saida += [f"- `{n}`: `{esc(d)}`" for n, d in checks]
            indices = conn.execute(SQL_INDICES, (schema, nome)).fetchall()
            if indices:
                saida += ["", "**Índices**", ""]
                saida += [f"- `{n}` ({am}): `{esc(d.split(' USING ', 1)[-1])}`" for n, am, d in indices]
            saida.append("")
    return "\n".join(saida)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--saida", type=Path, default=Path("docs/05-dicionario-de-dados.md"))
    args = p.parse_args()
    args.saida.write_text(gerar(), encoding="utf-8")
    print(f"Dicionário gravado em {args.saida}")


if __name__ == "__main__":
    main()
