-- Testes da carga da amostra sintética (executar após scripts/carregar_amostra.sh).
\set ON_ERROR_STOP 1
\echo '030 carga da amostra'

DO $$
DECLARE
    v_lote_v1 bigint;
    v_qtd integer;
BEGIN
    SELECT min(id_lote) INTO v_lote_v1 FROM controle.lote_carga WHERE arquivo = 'atlas_amostra_v1.csv';

    -- Idempotência: o mesmo arquivo gerou um único lote.
    SELECT count(*) INTO v_qtd FROM controle.lote_carga WHERE arquivo = 'atlas_amostra_v1.csv';
    ASSERT v_qtd = 1, 'Arquivo repetido gerou ' || v_qtd || ' lotes';

    -- Contagens do lote v1 conferem com data/sample/expectativa_amostra_v1.json.
    PERFORM 1 FROM controle.lote_carga
    WHERE id_lote = v_lote_v1 AND status = 'PROCESSADO'
      AND linhas_lidas = 20 AND linhas_aceitas = 9 AND linhas_rejeitadas = 11;
    ASSERT FOUND, 'Contagens do lote v1 divergentes';

    -- Cada regra rejeitou exatamente as linhas planejadas.
    SELECT count(*) INTO v_qtd FROM (
        SELECT regra, count(*) AS n FROM controle.rejeicao WHERE id_lote = v_lote_v1 GROUP BY regra
        EXCEPT
        SELECT * FROM (VALUES ('R01_MUN_AUSENTE', 1::bigint), ('R02_MUN_INEXISTENTE', 1), ('R03_UF_DIVERGENTE', 1),
                              ('R04_COBRADE_INEXISTENTE', 1), ('R05_COBRADE_NAO_FOLHA', 1),
                              ('R06_DATA_EVENTO_INVALIDA', 1), ('R07_DATA_EVENTO_FUTURA', 1),
                              ('R08_REGISTRO_ANTES_DO_EVENTO', 1), ('R10_DANO_INVALIDO', 2),
                              ('R11_DUPLICADO_NO_LOTE', 1)) e(regra, n)
    ) dif;
    ASSERT v_qtd = 0, 'Distribuição de rejeições por regra difere da esperada';

    -- Rejeição preserva o registro original completo.
    PERFORM 1 FROM controle.rejeicao
    WHERE id_lote = v_lote_v1 AND regra = 'R02_MUN_INEXISTENTE' AND registro ->> 'cd_mun' = '9999999';
    ASSERT FOUND, 'Registro original não preservado na rejeição';

    -- Ajuste rastreado: código de 6 dígitos completado.
    PERFORM 1 FROM controle.ajuste
    WHERE id_lote = v_lote_v1 AND valor_original = '530010' AND valor_ajustado = '5300108';
    ASSERT FOUND, 'Ajuste de código de 6 dígitos não registrado';

    -- Coluna não mapeada preservada em extras.
    PERFORM 1 FROM staging.atlas_ocorrencia WHERE id_lote = v_lote_v1 AND extras ? 'setores_censitarios';
    ASSERT FOUND, 'Coluna não mapeada foi perdida';

    -- Números no padrão brasileiro interpretados corretamente.
    PERFORM 1 FROM core.ocorrencia o JOIN core.ocorrencia_dano d USING (id_ocorrencia)
    WHERE o.chave_origem = 'RS-F-4314902-12100-20240502'
      AND d.cd_indicador = 'PEPL_TOTAL' AND d.valor = 12345678.90;
    ASSERT FOUND, 'Valor monetário pt-BR mal interpretado';

    -- Zero informado é gravado; vazio não é.
    SELECT count(*) INTO v_qtd FROM core.ocorrencia o JOIN core.ocorrencia_dano d USING (id_ocorrencia)
    WHERE o.chave_origem = 'RJ-F-3304557-13215-20240120';
    ASSERT v_qtd = 11, 'Zeros informados deveriam gerar 11 linhas de dano, gerou ' || v_qtd;

    -- Protocolo normalizado para maiúsculas.
    PERFORM 1 FROM core.ocorrencia WHERE protocolo = 'RJ-F-3304557-13215-20240120';
    ASSERT FOUND, 'Protocolo não normalizado';

    -- Registro sem protocolo recebe chave por hash.
    PERFORM 1 FROM core.ocorrencia WHERE protocolo IS NULL AND chave_origem LIKE 'H:%';
    ASSERT FOUND, 'Chave por hash ausente';

    -- Total: 9 da v1 + 1 novo da v2.
    SELECT count(*) INTO v_qtd FROM core.ocorrencia;
    ASSERT v_qtd = 10, 'Esperadas 10 ocorrências, há ' || v_qtd;

    -- Áreas de risco: 3 aceitas, município inferido para setor sem geocódigo.
    SELECT count(*) INTO v_qtd FROM risco.area_risco;
    ASSERT v_qtd = 3, 'Esperadas 3 áreas de risco';
    PERFORM 1 FROM risco.area_risco WHERE id_externo = 'SC-FLN-001' AND cd_mun = '4205407';
    ASSERT FOUND, 'Município não inferido pela geometria';

    -- Território: geometria inválida corrigida, feição órfã rejeitada.
    PERFORM 1 FROM core.municipio WHERE cd_mun = '2927408' AND ST_IsValid(geom) AND NOT ST_IsEmpty(geom);
    ASSERT FOUND, 'Geometria em laço não foi corrigida';
    PERFORM 1 FROM controle.rejeicao WHERE regra = 'T11_MALHA_SEM_CADASTRO';
    ASSERT FOUND, 'Feição sem cadastro não foi rejeitada';
END $$;
