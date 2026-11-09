"""Funções compartilhadas pelas cargas: conexão, lotes e normalização de nomes."""

from __future__ import annotations

import hashlib
import os
import re
import unicodedata
from pathlib import Path

import psycopg


def conectar() -> psycopg.Connection:
    """Conecta usando DATABASE_URL ou as variáveis padrão do libpq (PGHOST, PGUSER...)."""
    return psycopg.connect(os.environ.get("DATABASE_URL", ""), autocommit=False)


def hash_arquivo(caminho: Path) -> str:
    h = hashlib.sha256()
    with open(caminho, "rb") as f:
        for bloco in iter(lambda: f.read(1 << 20), b""):
            h.update(bloco)
    return h.hexdigest()


def normalizar_nome(nome: object) -> str:
    """'Cód. IBGE Município' -> 'cod_ibge_municipio'."""
    texto = unicodedata.normalize("NFKD", str(nome)).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "_", texto.lower()).strip("_")


def abrir_lote(conn: psycopg.Connection, fonte: str, caminho: Path,
               colunas_nao_mapeadas: list[str] | None = None) -> int | None:
    """Registra o lote. Retorna None se o mesmo arquivo já foi carregado para a fonte."""
    sha = hash_arquivo(caminho)
    linha = conn.execute(
        """INSERT INTO controle.lote_carga (fonte, arquivo, hash_sha256, status, colunas_nao_mapeadas)
           VALUES (%s, %s, %s, 'EM_STAGING', %s)
           ON CONFLICT (fonte, hash_sha256) DO NOTHING
           RETURNING id_lote""",
        (fonte, caminho.name, sha, colunas_nao_mapeadas or []),
    ).fetchone()
    return linha[0] if linha else None


def resumo_rejeicoes(conn: psycopg.Connection, id_lote: int) -> list[tuple[str, int]]:
    return conn.execute(
        "SELECT regra, count(*) FROM controle.rejeicao WHERE id_lote = %s GROUP BY regra ORDER BY 2 DESC, 1",
        (id_lote,),
    ).fetchall()


def imprimir_resultado(nome: str, id_lote: int, resultado: tuple, conn: psycopg.Connection) -> None:
    print(f"[{nome}] lote {id_lote}: aceitas={resultado[0]} rejeitadas={resultado[1]}"
          + (f" ajustadas={resultado[2]}" if len(resultado) > 2 else ""))
    for regra, qtd in resumo_rejeicoes(conn, id_lote):
        print(f"    {regra}: {qtd}")
