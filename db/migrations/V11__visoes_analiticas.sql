-- =====================================================================
-- V11 - Visões analíticas
-- Materializadas porque agregam todo o histórico e são lidas com muito
-- mais frequência do que os dados mudam (cargas anuais/periódicas).
-- Atualização: SELECT analitico.fn_atualizar();
-- =====================================================================

CREATE MATERIALIZED VIEW analitico.mv_recorrencia_municipio AS
SELECT o.cd_mun,
       m.cd_uf,
       h.grupo                       AS grupo_cobrade,
       count(*)                      AS qtd_ocorrencias,
       count(DISTINCT extract(year FROM o.dt_evento)) AS anos_com_ocorrencia,
       min(o.dt_evento)              AS primeira_ocorrencia,
       max(o.dt_evento)              AS ultima_ocorrencia,
       coalesce(sum(d.valor) FILTER (WHERE i.compoe_total_humano), 0)::bigint AS total_pessoas_afetadas,
       coalesce(sum(d.valor) FILTER (WHERE d.cd_indicador = 'DH_MORTOS'), 0)::bigint AS total_obitos
FROM core.ocorrencia o
JOIN core.municipio m ON m.cd_mun = o.cd_mun
JOIN core.vw_cobrade_hierarquia h ON h.cd_cobrade = o.cd_cobrade
LEFT JOIN core.ocorrencia_dano d ON d.id_ocorrencia = o.id_ocorrencia
LEFT JOIN core.indicador_dano i ON i.cd_indicador = d.cd_indicador
GROUP BY o.cd_mun, m.cd_uf, h.grupo
WITH NO DATA;

CREATE UNIQUE INDEX uq_mv_recorrencia ON analitico.mv_recorrencia_municipio (cd_mun, grupo_cobrade);

COMMENT ON MATERIALIZED VIEW analitico.mv_recorrencia_municipio IS 'Recorrência de desastres por município e grupo COBRADE (quantidade, anos com ocorrência, pessoas afetadas, óbitos).';

CREATE FUNCTION analitico.fn_atualizar() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_matviews WHERE schemaname = 'analitico'
               AND matviewname = 'mv_recorrencia_municipio' AND ispopulated) THEN
        REFRESH MATERIALIZED VIEW CONCURRENTLY analitico.mv_recorrencia_municipio;
    ELSE
        REFRESH MATERIALIZED VIEW analitico.mv_recorrencia_municipio;
    END IF;
END;
$$;

COMMENT ON FUNCTION analitico.fn_atualizar() IS 'Atualiza as visões materializadas (concorrente quando já populadas, sem bloquear leitores).';
