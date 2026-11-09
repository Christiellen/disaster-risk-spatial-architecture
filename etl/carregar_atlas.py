"""Carga do Atlas Digital de Desastres no Brasil (CSV ou XLSX).

Uso:
    python -m etl.carregar_atlas --arquivo data/raw/atlas/arquivo.xlsx --perfil
    python -m etl.carregar_atlas --arquivo data/raw/atlas/arquivo.xlsx

--perfil apenas lê o arquivo e descreve colunas, mapeamento e qualidade
aparente, sem tocar no banco. Use antes da primeira carga.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import pandas as pd
import yaml

from etl.comum import abrir_lote, conectar, imprimir_resultado, normalizar_nome

CONFIG = Path(__file__).parent / "config" / "atlas_colunas.yaml"


def carregar_mapa() -> tuple[dict[str, str], dict[str, str]]:
    cfg = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
    campos = {alias: canonico for canonico, aliases in cfg["campos"].items() for alias in aliases}
    danos = {alias: indicador for indicador, aliases in cfg["danos"].items() for alias in aliases}
    return campos, danos


def ler_arquivo(caminho: Path, aba: str | None) -> pd.DataFrame:
    """Lê tudo como texto. Em planilhas, localiza a linha de cabeçalho real
    (arquivos oficiais costumam trazer linhas de título antes da tabela)."""
    campos, danos = carregar_mapa()
    conhecidos = set(campos) | set(danos)

    if caminho.suffix.lower() in (".xlsx", ".xls"):
        bruto = pd.read_excel(caminho, sheet_name=aba or 0, header=None, dtype=str)
    else:
        texto = None
        for codificacao in ("utf-8-sig", "latin-1"):
            try:
                texto = caminho.read_text(encoding=codificacao)
                break
            except UnicodeDecodeError:
                continue
        if texto is None:
            sys.exit("Não foi possível decodificar o CSV (UTF-8 ou Latin-1).")
        # Separador: o que produz mais nomes reconhecidos em alguma das primeiras linhas.
        # Linhas de título antes do cabeçalho são puladas.
        melhor = (0, ";", 0)
        for sep in (";", ",", "\t", "|"):
            for idx, linha in enumerate(texto.splitlines()[:30]):
                acertos = len({normalizar_nome(c) for c in linha.split(sep)} & conhecidos)
                if acertos > melhor[0]:
                    melhor = (acertos, sep, idx)
        _, sep, pular = melhor
        bruto = pd.read_csv(caminho, header=None, dtype=str, sep=sep, encoding=codificacao,
                            keep_default_na=False, skiprows=pular)

    linha_cabecalho = 0
    for i in range(min(30, len(bruto))):
        nomes = {normalizar_nome(v) for v in bruto.iloc[i].tolist() if isinstance(v, str)}
        if len(nomes & conhecidos) >= 3:
            linha_cabecalho = i
            break

    df = bruto.iloc[linha_cabecalho + 1:].copy()
    df.columns = [normalizar_nome(c) if isinstance(c, str) and c.strip() else f"coluna_{j}"
                  for j, c in enumerate(bruto.iloc[linha_cabecalho].tolist())]
    df = df.loc[:, ~df.columns.duplicated()]
    df = df.dropna(how="all")
    df = df[~(df.fillna("").astype(str).apply(lambda s: s.str.strip()) == "").all(axis=1)]
    return df.reset_index(drop=True).fillna("")


def classificar_colunas(colunas: list[str]) -> tuple[dict[str, str], dict[str, str], list[str]]:
    campos, danos = carregar_mapa()
    m_campos = {c: campos[c] for c in colunas if c in campos}
    m_danos = {c: danos[c] for c in colunas if c in danos}
    nao_mapeadas = [c for c in colunas if c not in m_campos and c not in m_danos]
    return m_campos, m_danos, nao_mapeadas


def perfilar(df: pd.DataFrame) -> None:
    m_campos, m_danos, nao_mapeadas = classificar_colunas(list(df.columns))
    print(f"# Perfil do arquivo\n\nLinhas de dados: {len(df)}\n")
    print("| Coluna no arquivo | Destino | % vazio | Distintos | Exemplos |")
    print("|---|---|---|---|---|")
    for col in df.columns:
        serie = df[col].astype(str).str.strip()
        vazio = (serie == "").mean() * 100
        exemplos = ", ".join(serie[serie != ""].drop_duplicates().head(3).tolist())
        destino = m_campos.get(col) or (f"dano:{m_danos[col]}" if col in m_danos else "extras (não mapeada)")
        print(f"| {col} | {destino} | {vazio:.1f} | {serie.nunique()} | {exemplos[:60]} |")

    faltando = sorted({"cd_mun", "dt_evento", "cobrade"} - set(m_campos.values()))
    if faltando:
        print(f"\nATENÇÃO: campos obrigatórios sem coluna mapeada: {', '.join(faltando)}. "
              "Ajuste etl/config/atlas_colunas.yaml.")

    col_data = next((c for c, d in m_campos.items() if d == "dt_evento"), None)
    if col_data:
        amostra = df[col_data].astype(str).str.strip()
        formatos = amostra.map(lambda v: "dd/mm/aaaa" if re.match(r"^\d{2}/\d{2}/\d{4}", v)
                               else "aaaa-mm-dd" if re.match(r"^\d{4}-\d{2}-\d{2}", v)
                               else "série Excel" if re.match(r"^\d{4,5}(\.0+)?$", v)
                               else "vazio" if v == "" else "outro")
        print("\nFormatos de data do evento:", formatos.value_counts().to_dict())


def carregar(df: pd.DataFrame, caminho: Path, fonte: str) -> int:
    m_campos, m_danos, nao_mapeadas = classificar_colunas(list(df.columns))
    faltando = {"cd_mun", "dt_evento", "cobrade"} - set(m_campos.values())
    if faltando:
        sys.exit(f"Campos obrigatórios sem mapeamento: {sorted(faltando)}. Rode com --perfil.")

    with conectar() as conn:
        id_lote = abrir_lote(conn, fonte, caminho, nao_mapeadas)
        if id_lote is None:
            print(f"Arquivo {caminho.name} já carregado para {fonte} (mesmo hash). Nada a fazer.")
            return 0

        colunas = ["id_lote", "linha_origem", "protocolo", "uf", "cd_mun", "nome_mun", "dt_evento",
                   "dt_registro", "cobrade", "cobrade_desc", "situacao", "danos", "extras"]
        with conn.cursor().copy(f"COPY staging.atlas_ocorrencia ({', '.join(colunas)}) FROM STDIN") as copy:
            for i, registro in enumerate(df.to_dict(orient="records"), start=1):
                linha = {canon: None for canon in colunas[2:11]}
                for col, canon in m_campos.items():
                    valor = str(registro[col]).strip()
                    linha[canon] = valor or None
                danos = {ind: str(registro[col]).strip() for col, ind in m_danos.items()
                         if str(registro[col]).strip() != ""}
                extras = {col: registro[col] for col in nao_mapeadas if str(registro[col]).strip() != ""}
                copy.write_row([id_lote, i, *linha.values(),
                                json.dumps(danos, ensure_ascii=False),
                                json.dumps(extras, ensure_ascii=False)])

        resultado = conn.execute("SELECT * FROM core.fn_processar_lote_atlas(%s)", (id_lote,)).fetchone()
        conn.execute("SELECT analitico.fn_atualizar()")
        imprimir_resultado("atlas", id_lote, resultado, conn)
        if nao_mapeadas:
            print(f"    colunas preservadas em extras: {', '.join(nao_mapeadas)}")
        conn.commit()
        return id_lote


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--arquivo", required=True, type=Path)
    p.add_argument("--aba", help="Nome da aba (XLSX). Padrão: a primeira.")
    p.add_argument("--fonte", default="ATLAS_DESASTRES", choices=["ATLAS_DESASTRES", "AMOSTRA"])
    p.add_argument("--perfil", action="store_true", help="Somente descreve o arquivo, sem carregar.")
    args = p.parse_args()

    df = ler_arquivo(args.arquivo, args.aba)
    if args.perfil:
        perfilar(df)
    else:
        carregar(df, args.arquivo, args.fonte)


if __name__ == "__main__":
    main()
