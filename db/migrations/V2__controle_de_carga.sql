-- =====================================================================
-- V2 - Controle de carga
-- Todo dado que entra no core pertence a um lote rastreável.
-- O hash SHA-256 do arquivo garante idempotência: o mesmo arquivo
-- não é carregado duas vezes para a mesma fonte.
-- =====================================================================

CREATE TABLE controle.lote_carga (
    id_lote          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fonte            text        NOT NULL CHECK (fonte IN ('ATLAS_DESASTRES', 'IBGE_MUNICIPIOS', 'IBGE_MALHA_MUN', 'IBGE_MALHA_UF', 'SGB_AREAS_RISCO', 'AMOSTRA')),
    arquivo          text        NOT NULL,
    hash_sha256      char(64)    NOT NULL CHECK (hash_sha256 ~ '^[0-9a-f]{64}$'),
    status           text        NOT NULL DEFAULT 'RECEBIDO'
                                 CHECK (status IN ('RECEBIDO', 'EM_STAGING', 'PROCESSADO', 'FALHOU')),
    linhas_lidas     integer     CHECK (linhas_lidas >= 0),
    linhas_aceitas   integer     CHECK (linhas_aceitas >= 0),
    linhas_rejeitadas integer    CHECK (linhas_rejeitadas >= 0),
    colunas_nao_mapeadas text[]  NOT NULL DEFAULT '{}',
    iniciado_em      timestamptz NOT NULL DEFAULT now(),
    concluido_em     timestamptz,
    observacao       text,
    CONSTRAINT uq_lote_fonte_hash UNIQUE (fonte, hash_sha256),
    CONSTRAINT ck_lote_conclusao CHECK (concluido_em IS NULL OR concluido_em >= iniciado_em),
    CONSTRAINT ck_lote_contagem CHECK (
        status <> 'PROCESSADO'
        OR (linhas_aceitas IS NOT NULL AND linhas_rejeitadas IS NOT NULL
            AND linhas_aceitas + linhas_rejeitadas <= linhas_lidas)
    )
);

COMMENT ON TABLE  controle.lote_carga IS 'Um registro por arquivo recebido. Base da rastreabilidade de qualquer linha do core até o arquivo de origem.';
COMMENT ON COLUMN controle.lote_carga.id_lote IS 'Identificador do lote.';
COMMENT ON COLUMN controle.lote_carga.fonte IS 'Fonte de dados do arquivo (domínio fechado).';
COMMENT ON COLUMN controle.lote_carga.arquivo IS 'Nome do arquivo recebido.';
COMMENT ON COLUMN controle.lote_carga.hash_sha256 IS 'Hash SHA-256 do conteúdo do arquivo. Impede recarga do mesmo arquivo (idempotência).';
COMMENT ON COLUMN controle.lote_carga.status IS 'Ciclo de vida do lote: RECEBIDO -> EM_STAGING -> PROCESSADO | FALHOU.';
COMMENT ON COLUMN controle.lote_carga.linhas_lidas IS 'Quantidade de linhas lidas do arquivo.';
COMMENT ON COLUMN controle.lote_carga.linhas_aceitas IS 'Linhas que passaram nas regras e foram gravadas no core.';
COMMENT ON COLUMN controle.lote_carga.linhas_rejeitadas IS 'Linhas enviadas para controle.rejeicao.';
COMMENT ON COLUMN controle.lote_carga.colunas_nao_mapeadas IS 'Colunas do arquivo sem mapeamento canônico. Preservadas em staging.*.extras para não perder informação.';
COMMENT ON COLUMN controle.lote_carga.iniciado_em IS 'Início do processamento.';
COMMENT ON COLUMN controle.lote_carga.concluido_em IS 'Fim do processamento.';
COMMENT ON COLUMN controle.lote_carga.observacao IS 'Texto livre (ex.: mensagem de erro em caso de falha).';

CREATE TABLE controle.rejeicao (
    id_rejeicao   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_lote       bigint      NOT NULL REFERENCES controle.lote_carga (id_lote) ON DELETE CASCADE,
    linha_origem  integer     NOT NULL CHECK (linha_origem > 0),
    regra         text        NOT NULL,
    detalhe       text,
    registro      jsonb       NOT NULL,
    rejeitado_em  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ix_rejeicao_lote_regra ON controle.rejeicao (id_lote, regra);

COMMENT ON TABLE  controle.rejeicao IS 'Quarentena: linhas que violaram regras de qualidade, com o código da regra e o registro original completo.';
COMMENT ON COLUMN controle.rejeicao.id_rejeicao IS 'Identificador da rejeição.';
COMMENT ON COLUMN controle.rejeicao.id_lote IS 'Lote de origem.';
COMMENT ON COLUMN controle.rejeicao.linha_origem IS 'Número da linha no arquivo de origem (1 = primeira linha de dados).';
COMMENT ON COLUMN controle.rejeicao.regra IS 'Código da regra de qualidade violada (catálogo em docs/06-regras-de-integridade.md).';
COMMENT ON COLUMN controle.rejeicao.detalhe IS 'Descrição legível da violação.';
COMMENT ON COLUMN controle.rejeicao.registro IS 'Registro original, como recebido, em JSON.';
COMMENT ON COLUMN controle.rejeicao.rejeitado_em IS 'Momento da rejeição.';
