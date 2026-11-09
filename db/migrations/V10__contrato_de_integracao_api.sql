-- =====================================================================
-- V10 - Contrato de integração v1 (ver ADR-0008 e contracts/)
-- Consumidores externos (app mobile, painéis, outros sistemas) leem
-- apenas o schema api. O core pode evoluir sem quebrar o contrato:
-- mudanças incompatíveis geram v2 ao lado da v1.
-- =====================================================================

CREATE VIEW api.v1_ocorrencia AS
SELECT o.chave_origem                         AS id,
       o.protocolo,
       o.cd_mun,
       m.nome                                 AS municipio,
       u.sigla_uf                             AS uf,
       o.cd_cobrade,
       h.descricao                            AS tipologia,
       h.grupo                                AS grupo_cobrade,
       o.dt_evento,
       o.dt_registro,
       o.situacao,
       coalesce(d.danos, '{}'::jsonb)         AS danos,
       coalesce(d.total_pessoas_afetadas, 0)  AS total_pessoas_afetadas,
       round(ST_X(m.ponto_ref)::numeric, 6)   AS longitude,
       round(ST_Y(m.ponto_ref)::numeric, 6)   AS latitude,
       o.versao,
       o.atualizado_em
FROM core.ocorrencia o
JOIN core.municipio m ON m.cd_mun = o.cd_mun
JOIN core.uf u        ON u.cd_uf = m.cd_uf
JOIN core.vw_cobrade_hierarquia h ON h.cd_cobrade = o.cd_cobrade
LEFT JOIN LATERAL (
    SELECT jsonb_object_agg(od.cd_indicador, od.valor ORDER BY od.cd_indicador) AS danos,
           sum(od.valor) FILTER (WHERE i.compoe_total_humano)::bigint          AS total_pessoas_afetadas
    FROM core.ocorrencia_dano od
    JOIN core.indicador_dano i ON i.cd_indicador = od.cd_indicador
    WHERE od.id_ocorrencia = o.id_ocorrencia
) d ON true;

COMMENT ON VIEW api.v1_ocorrencia IS 'Contrato v1 da ocorrência. Identificador público = chave_origem; a chave substituta interna não é exposta.';

-- Consulta espacial para mapas: FeatureCollection GeoJSON
CREATE FUNCTION api.fn_v1_ocorrencias_geojson(
    p_bbox       float8[] DEFAULT NULL,   -- {xmin, ymin, xmax, ymax} em graus (SIRGAS 2000)
    p_desde      date     DEFAULT NULL,
    p_cd_cobrade text     DEFAULT NULL,   -- aceita prefixo (ex.: '12' = todo o grupo hidrológico)
    p_limite     integer  DEFAULT 1000
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
    v_env geometry;
    v_res jsonb;
BEGIN
    IF p_limite NOT BETWEEN 1 AND 10000 THEN
        RAISE EXCEPTION 'p_limite deve estar entre 1 e 10000' USING ERRCODE = 'invalid_parameter_value';
    END IF;
    IF p_bbox IS NOT NULL THEN
        IF array_length(p_bbox, 1) <> 4 OR p_bbox[1] >= p_bbox[3] OR p_bbox[2] >= p_bbox[4] THEN
            RAISE EXCEPTION 'p_bbox deve ser {xmin, ymin, xmax, ymax}' USING ERRCODE = 'invalid_parameter_value';
        END IF;
        v_env := ST_MakeEnvelope(p_bbox[1], p_bbox[2], p_bbox[3], p_bbox[4], 4674);
    END IF;

    SELECT jsonb_build_object(
               'type', 'FeatureCollection',
               'versao_contrato', 'v1',
               'features', coalesce(jsonb_agg(f.feature), '[]'::jsonb))
      INTO v_res
    FROM (
        SELECT jsonb_build_object(
                   'type', 'Feature',
                   'id', v.id,
                   'geometry', ST_AsGeoJSON(m.ponto_ref, 6)::jsonb,
                   'properties', to_jsonb(v) - 'longitude' - 'latitude') AS feature
        FROM api.v1_ocorrencia v
        JOIN core.municipio m ON m.cd_mun = v.cd_mun
        WHERE (v_env IS NULL OR m.ponto_ref && v_env)
          AND (p_desde IS NULL OR v.dt_evento >= p_desde)
          -- prefixo como faixa (sargável): '12' -> '12000'..'12999' (ver docs/07)
          AND (p_cd_cobrade IS NULL OR v.cd_cobrade BETWEEN rpad(p_cd_cobrade, 5, '0') AND rpad(p_cd_cobrade, 5, '9'))
        ORDER BY v.dt_evento DESC, v.id
        LIMIT p_limite
    ) f;

    RETURN v_res;
END;
$$;

COMMENT ON FUNCTION api.fn_v1_ocorrencias_geojson(float8[], date, text, integer) IS 'Ocorrências como FeatureCollection GeoJSON (ponto de referência do município), com filtros por bbox, data e prefixo COBRADE.';

-- Sincronização incremental para clientes offline-first
CREATE FUNCTION api.fn_v1_sincronizar(p_cursor bigint DEFAULT 0, p_limite integer DEFAULT 500)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
    v_res jsonb;
BEGIN
    IF p_limite NOT BETWEEN 1 AND 5000 THEN
        RAISE EXCEPTION 'p_limite deve estar entre 1 e 5000' USING ERRCODE = 'invalid_parameter_value';
    END IF;

    WITH eventos AS (
        SELECT h.hist_id, h.chave_origem, h.hist_operacao
        FROM hist.ocorrencia h
        WHERE h.hist_id > p_cursor
        ORDER BY h.hist_id
        LIMIT p_limite + 1
    ),
    pagina AS (
        SELECT * FROM eventos ORDER BY hist_id LIMIT p_limite
    ),
    ultimo_por_chave AS (
        SELECT DISTINCT ON (chave_origem) chave_origem, hist_operacao, hist_id
        FROM pagina
        ORDER BY chave_origem, hist_id DESC
    )
    SELECT jsonb_build_object(
               'versao_contrato', 'v1',
               'cursor', coalesce((SELECT max(hist_id) FROM pagina), p_cursor),
               'tem_mais', (SELECT count(*) FROM eventos) > p_limite,
               'alteracoes', coalesce(jsonb_agg(
                   jsonb_build_object(
                       'operacao', CASE WHEN v.id IS NULL THEN 'EXCLUIR' ELSE 'GRAVAR' END,
                       'id', u.chave_origem,
                       'registro', to_jsonb(v))
                   ORDER BY u.hist_id), '[]'::jsonb))
      INTO v_res
    FROM ultimo_por_chave u
    LEFT JOIN api.v1_ocorrencia v ON v.id = u.chave_origem;

    RETURN v_res;
END;
$$;

COMMENT ON FUNCTION api.fn_v1_sincronizar(bigint, integer) IS 'Feed incremental: alterações desde o cursor (GRAVAR com o registro atual ou EXCLUIR). O cliente guarda o cursor retornado.';
