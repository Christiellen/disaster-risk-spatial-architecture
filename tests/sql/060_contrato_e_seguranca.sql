-- Testes do contrato de integração e do modelo de permissões.
\set ON_ERROR_STOP 1
\echo '060 contrato e seguranca'

DO $$
DECLARE v jsonb; v_qtd integer;
BEGIN
    -- GeoJSON: FeatureCollection válida, filtrada por bbox de SC.
    v := api.fn_v1_ocorrencias_geojson(ARRAY[-49.0, -28.0, -48.3, -27.4]::float8[]);
    ASSERT v ->> 'type' = 'FeatureCollection', 'Tipo GeoJSON incorreto';
    ASSERT jsonb_array_length(v -> 'features') = 4, 'SC deveria ter 4 ocorrências, tem ' || jsonb_array_length(v -> 'features');
    ASSERT (v #>> '{features,0,geometry,type}') = 'Point', 'Geometria deveria ser Point';

    -- Filtro por prefixo COBRADE (grupo hidrológico).
    v := api.fn_v1_ocorrencias_geojson(p_cd_cobrade => '12');
    SELECT count(*) INTO v_qtd FROM jsonb_array_elements(v -> 'features') f
    WHERE f #>> '{properties,cd_cobrade}' NOT LIKE '12%';
    ASSERT v_qtd = 0, 'Filtro por prefixo COBRADE vazou';

    -- Parâmetro inválido é recusado com erro claro.
    BEGIN
        PERFORM api.fn_v1_ocorrencias_geojson(ARRAY[1, 2, 0, 0]::float8[]);
        RAISE EXCEPTION 'Aceitou bbox invertida';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- Sincronização: do zero, entrega todas as ocorrências vigentes, uma vez cada.
    v := api.fn_v1_sincronizar(0, 5000);
    SELECT count(DISTINCT a ->> 'id') INTO v_qtd FROM jsonb_array_elements(v -> 'alteracoes') a;
    ASSERT v_qtd = 10, 'Sincronização inicial deveria trazer 10 registros, trouxe ' || v_qtd;
    ASSERT (v ->> 'tem_mais')::boolean = false, 'Não deveria haver mais páginas';

    -- Paginação: páginas de 3 avançam o cursor e terminam.
    v := api.fn_v1_sincronizar(0, 3);
    ASSERT (v ->> 'tem_mais')::boolean, 'Página de 3 deveria indicar mais dados';
    v := api.fn_v1_sincronizar((v ->> 'cursor')::bigint, 5000);
    ASSERT (v ->> 'tem_mais')::boolean = false, 'Segunda página deveria encerrar';

    -- Total de pessoas afetadas é calculado, não armazenado.
    PERFORM 1 FROM api.v1_ocorrencia
    WHERE id = 'RS-F-4314902-12100-20240502' AND total_pessoas_afetadas = 5 + 120 + 30 + 15432 + 78900 + 2;
    ASSERT FOUND, 'Total de pessoas afetadas incorreto';
END $$;

-- Consumidor externo enxerga o contrato e nada além dele.
SET ROLE s2id_consumidor;
DO $$
BEGIN
    PERFORM count(*) FROM api.v1_ocorrencia;
    PERFORM api.fn_v1_sincronizar(0, 10);
    BEGIN
        PERFORM count(*) FROM core.ocorrencia;
        RAISE EXCEPTION 'Consumidor leu o core diretamente';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
        PERFORM count(*) FROM controle.rejeicao;
        RAISE EXCEPTION 'Consumidor leu a quarentena';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END $$;
RESET ROLE;

-- Analista lê, mas não escreve.
SET ROLE s2id_analista;
DO $$
BEGIN
    PERFORM count(*) FROM core.ocorrencia;
    BEGIN
        UPDATE core.ocorrencia SET situacao = 'x' WHERE false;
        RAISE EXCEPTION 'Analista conseguiu escrever no core';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
END $$;
RESET ROLE;
