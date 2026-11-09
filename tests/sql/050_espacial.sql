-- Testes das consultas espaciais demonstradas em docs/09-consultas-espaciais.md.
\set ON_ERROR_STOP 1
\echo '050 espacial'

DO $$
DECLARE v_qtd integer; v_lista text;
BEGIN
    -- Toda geometria persistida é válida.
    SELECT count(*) INTO v_qtd FROM core.municipio WHERE geom IS NOT NULL AND NOT ST_IsValid(geom);
    ASSERT v_qtd = 0, 'Municípios com geometria inválida';

    -- Todo município está contido (com tolerância) na geometria da sua UF.
    SELECT string_agg(m.cd_mun, ',') INTO v_lista
    FROM core.municipio m JOIN core.uf u USING (cd_uf)
    WHERE m.geom IS NOT NULL AND u.geom IS NOT NULL
      AND NOT ST_Covers(ST_Buffer(u.geom, 0.0001), m.geom);
    ASSERT v_lista IS NULL, 'Municípios fora da própria UF: ' || v_lista;

    -- Vizinhança: São José faz divisa com Florianópolis e Palhoça.
    SELECT string_agg(v.cd_mun, ',' ORDER BY v.cd_mun) INTO v_lista
    FROM core.municipio a JOIN core.municipio v ON v.cd_mun <> a.cd_mun AND ST_Touches(a.geom, v.geom)
    WHERE a.cd_mun = '4216602';
    ASSERT v_lista = '4205407,4211900', 'Vizinhos de São José: ' || coalesce(v_lista, '(nenhum)');

    -- Evento regional: ocorrências hidrológicas em municípios vizinhos com até 7 dias de diferença.
    SELECT count(*) INTO v_qtd
    FROM core.ocorrencia a
    JOIN core.municipio ma ON ma.cd_mun = a.cd_mun
    JOIN core.ocorrencia b ON b.id_ocorrencia > a.id_ocorrencia
                          AND b.cd_cobrade BETWEEN '12000' AND '12999'
                          AND a.cd_cobrade BETWEEN '12000' AND '12999'
                          AND abs(b.dt_evento - a.dt_evento) <= 7
    JOIN core.municipio mb ON mb.cd_mun = b.cd_mun AND ST_Touches(ma.geom, mb.geom);
    ASSERT v_qtd = 4, 'Esperados 4 pares de evento regional (SC 2023 e RS 2024), obtidos ' || v_qtd;

    -- Raio: municípios a até 30 km do centro de Florianópolis (geography = metros).
    SELECT string_agg(cd_mun, ',' ORDER BY cd_mun) INTO v_lista
    FROM core.municipio
    WHERE ST_DWithin(ponto_ref::geography, ST_SetSRID(ST_MakePoint(-48.55, -27.60), 4674)::geography, 30000);
    ASSERT v_lista = '4205407,4216602,4211900' OR v_lista = '4205407,4211900,4216602',
           'Municípios no raio: ' || coalesce(v_lista, '(nenhum)');

    -- Ocorrências dentro de áreas de risco mapeadas com a mesma tipologia.
    SELECT count(*) INTO v_qtd
    FROM risco.area_risco ar
    JOIN core.ocorrencia o ON o.cd_mun = ar.cd_mun AND o.cd_cobrade = ar.cd_cobrade_relacionado;
    ASSERT v_qtd = 2, 'Esperadas 2 ocorrências em área de risco de mesma tipologia, obtidas ' || v_qtd;
END $$;
