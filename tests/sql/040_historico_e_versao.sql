-- Testes de histórico, versionamento e concorrência otimista.
-- Executa alterações dentro de uma transação e desfaz ao final.
\set ON_ERROR_STOP 1
\echo '040 historico e versao'

BEGIN;

DO $$
DECLARE
    v_chave constant text := 'SC-F-4205407-12100-20230115';
    v_qtd integer;
    v_versao integer;
    v_antes jsonb;
BEGIN
    -- A v2 da amostra alterou danos de Florianópolis: versão 2 e changelog I + U.
    SELECT versao INTO v_versao FROM core.ocorrencia WHERE chave_origem = v_chave;
    ASSERT v_versao = 2, 'Esperada versão 2 após recarga v2, obtida ' || v_versao;
    SELECT count(*) INTO v_qtd FROM hist.ocorrencia WHERE chave_origem = v_chave;
    ASSERT v_qtd = 2, 'Esperados 2 eventos de histórico, obtidos ' || v_qtd;

    -- Desabrigados revisados de 40 para 55, prejuízo privado removido.
    PERFORM 1 FROM hist.ocorrencia_dano h JOIN core.ocorrencia o USING (id_ocorrencia)
    WHERE o.chave_origem = v_chave AND h.cd_indicador = 'DH_DESABRIGADOS' AND h.hist_operacao = 'U' AND h.valor = 55;
    ASSERT FOUND, 'Revisão de desabrigados não registrada no histórico';
    PERFORM 1 FROM hist.ocorrencia_dano h JOIN core.ocorrencia o USING (id_ocorrencia)
    WHERE o.chave_origem = v_chave AND h.cd_indicador = 'PEPR_TOTAL' AND h.hist_operacao = 'D';
    ASSERT FOUND, 'Remoção de prejuízo privado não registrada';

    -- Recarga sem mudança não gera versão: os demais continuam na versão 1.
    SELECT count(*) INTO v_qtd FROM core.ocorrencia WHERE versao > 1;
    ASSERT v_qtd = 1, 'Recarga idêntica não deveria gerar novas versões (' || v_qtd || ')';

    -- Alteração com a versão correta é aceita e incrementa.
    UPDATE core.ocorrencia SET situacao = 'Revisado', versao = 2 WHERE chave_origem = v_chave;
    SELECT versao INTO v_versao FROM core.ocorrencia WHERE chave_origem = v_chave;
    ASSERT v_versao = 3, 'Versão não incrementada';

    -- Alteração com versão desatualizada é recusada (cliente offline com dado velho).
    BEGIN
        UPDATE core.ocorrencia SET situacao = 'Conflito', versao = 2 WHERE chave_origem = v_chave;
        RAISE EXCEPTION 'Deveria ter recusado versão desatualizada';
    EXCEPTION WHEN serialization_failure THEN
        NULL;
    END;

    -- Campos imutáveis são protegidos.
    UPDATE core.ocorrencia SET chave_origem = 'OUTRA' WHERE chave_origem = v_chave;
    PERFORM 1 FROM core.ocorrencia WHERE chave_origem = v_chave;
    ASSERT FOUND, 'chave_origem não deveria ser alterável';

    -- Exclusão gera tombstone; consulta "as-of" enxerga o passado.
    SELECT hist.fn_ocorrencia_em(v_chave, now()) INTO v_antes;
    ASSERT v_antes ->> 'situacao' = 'Revisado', 'as-of não refletiu o estado atual';
    DELETE FROM core.ocorrencia WHERE chave_origem = v_chave;
    PERFORM 1 FROM hist.ocorrencia WHERE chave_origem = v_chave AND hist_operacao = 'D';
    ASSERT FOUND, 'Exclusão sem tombstone';
    ASSERT hist.fn_ocorrencia_em(v_chave, now()) IS NULL, 'as-of deveria retornar NULL após exclusão';

    -- Regras de integridade no próprio banco (não só na carga).
    BEGIN
        INSERT INTO core.ocorrencia (chave_origem, cd_mun, cd_cobrade, dt_evento, id_lote_origem, linha_origem)
        VALUES ('TESTE-1', '4205407', '12000', DATE '2023-01-01', 1, 1);
        RAISE EXCEPTION 'Aceitou COBRADE que não é folha';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO core.ocorrencia (chave_origem, cd_mun, cd_cobrade, dt_evento, dt_registro, id_lote_origem, linha_origem)
        VALUES ('TESTE-2', '4205407', '12100', DATE '2023-01-10', DATE '2023-01-01', 1, 1);
        RAISE EXCEPTION 'Aceitou registro anterior ao evento';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO core.ocorrencia_dano (id_ocorrencia, cd_indicador, valor)
        SELECT id_ocorrencia, 'DH_FERIDOS', 2.5 FROM core.ocorrencia LIMIT 1
        ON CONFLICT (id_ocorrencia, cd_indicador) DO UPDATE SET valor = EXCLUDED.valor;
        RAISE EXCEPTION 'Aceitou pessoa fracionada';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO core.municipio (cd_mun, cd_uf, nome) VALUES ('4299999', 43, 'UF errada');
        RAISE EXCEPTION 'Aceitou município com prefixo de outra UF';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END $$;

ROLLBACK;
