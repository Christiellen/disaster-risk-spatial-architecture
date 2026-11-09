-- =====================================================================
-- V9 - Promoção staging -> core
-- Cada função processa um lote inteiro em uma única transação:
-- ou o lote entra completo (aceitas + rejeitadas registradas), ou nada
-- entra. As regras estão catalogadas em docs/06-regras-de-integridade.md.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Território: cadastro de UFs e municípios (API de Localidades IBGE)
-- ---------------------------------------------------------------------
CREATE FUNCTION core.fn_processar_lote_ibge_municipios(p_id_lote bigint)
RETURNS TABLE (aceitas integer, rejeitadas integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_lidas integer;
BEGIN
    SELECT count(*) INTO v_lidas FROM staging.ibge_municipio WHERE id_lote = p_id_lote;

    CREATE TEMP TABLE t_mun ON COMMIT DROP AS
    SELECT s.*,
           staging.fn_normalizar_cd_mun(s.cd_mun) AS cd_mun_n,
           nullif(regexp_replace(coalesce(s.cd_uf, ''), '\D', '', 'g'), '') AS cd_uf_n,
           CASE
               WHEN staging.fn_normalizar_cd_mun(s.cd_mun) !~ '^\d{7}$' THEN 'T01_MUN_CODIGO_INVALIDO'
               WHEN staging.fn_texto(s.nome_mun) IS NULL                THEN 'T02_MUN_NOME_AUSENTE'
               WHEN coalesce(s.cd_uf, '') !~ '^\d{2}$'                  THEN 'T03_UF_CODIGO_INVALIDO'
               WHEN left(staging.fn_normalizar_cd_mun(s.cd_mun), 2) <> s.cd_uf THEN 'T04_MUN_PREFIXO_UF'
               WHEN upper(s.sigla_regiao) NOT IN ('N', 'NE', 'SE', 'S', 'CO') THEN 'T05_REGIAO_INVALIDA'
           END AS regra
    FROM staging.ibge_municipio s
    WHERE s.id_lote = p_id_lote;

    INSERT INTO controle.rejeicao (id_lote, linha_origem, regra, detalhe, registro)
    SELECT p_id_lote, t.linha_origem, t.regra, 'Cadastro de município inconsistente',
           to_jsonb(t) - 'cd_mun_n' - 'cd_uf_n' - 'regra'
    FROM t_mun t WHERE t.regra IS NOT NULL;

    INSERT INTO core.uf (cd_uf, sigla_uf, nome, sigla_regiao)
    SELECT DISTINCT ON (t.cd_uf_n::smallint) t.cd_uf_n::smallint, upper(t.sigla_uf), staging.fn_texto(t.nome_uf), upper(t.sigla_regiao)
    FROM t_mun t WHERE t.regra IS NULL
    ORDER BY t.cd_uf_n::smallint
    ON CONFLICT (cd_uf) DO UPDATE
       SET sigla_uf = EXCLUDED.sigla_uf, nome = EXCLUDED.nome, sigla_regiao = EXCLUDED.sigla_regiao
     WHERE (core.uf.sigla_uf, core.uf.nome, core.uf.sigla_regiao)
           IS DISTINCT FROM (EXCLUDED.sigla_uf, EXCLUDED.nome, EXCLUDED.sigla_regiao);

    INSERT INTO core.municipio (cd_mun, cd_uf, nome)
    SELECT DISTINCT ON (t.cd_mun_n) t.cd_mun_n, t.cd_uf_n::smallint, staging.fn_texto(t.nome_mun)
    FROM t_mun t WHERE t.regra IS NULL
    ORDER BY t.cd_mun_n, t.linha_origem
    ON CONFLICT (cd_mun) DO UPDATE
       SET nome = EXCLUDED.nome, cd_uf = EXCLUDED.cd_uf
     WHERE (core.municipio.nome, core.municipio.cd_uf) IS DISTINCT FROM (EXCLUDED.nome, EXCLUDED.cd_uf);

    SELECT count(*) FILTER (WHERE regra IS NULL), count(*) FILTER (WHERE regra IS NOT NULL)
      INTO aceitas, rejeitadas FROM t_mun;

    UPDATE controle.lote_carga
       SET status = 'PROCESSADO', linhas_lidas = v_lidas, linhas_aceitas = aceitas,
           linhas_rejeitadas = rejeitadas, concluido_em = now()
     WHERE id_lote = p_id_lote;

    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION core.fn_processar_lote_ibge_municipios(bigint) IS 'Promove o cadastro de UFs e municípios do staging para o core (upsert idempotente).';

-- ---------------------------------------------------------------------
-- Território: geometrias (API de Malhas IBGE)
-- ---------------------------------------------------------------------
CREATE FUNCTION core.fn_processar_lote_ibge_malha(p_id_lote bigint)
RETURNS TABLE (aceitas integer, rejeitadas integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_lidas integer;
BEGIN
    SELECT count(*) INTO v_lidas FROM staging.ibge_malha WHERE id_lote = p_id_lote;

    CREATE TEMP TABLE t_malha ON COMMIT DROP AS
    SELECT s.id_lote, s.linha_origem, s.nivel, s.codarea,
           staging.fn_geom_poligonal(s.geojson) AS geom,
           NULL::text AS regra
    FROM staging.ibge_malha s
    WHERE s.id_lote = p_id_lote;

    UPDATE t_malha t SET regra = CASE
        WHEN t.geom IS NULL THEN 'T10_GEOMETRIA_INVALIDA'
        WHEN t.nivel = 'MUN' AND NOT EXISTS (SELECT 1 FROM core.municipio m WHERE m.cd_mun = t.codarea) THEN 'T11_MALHA_SEM_CADASTRO'
        WHEN t.nivel = 'UF'  AND NOT EXISTS (SELECT 1 FROM core.uf u WHERE u.cd_uf::text = t.codarea) THEN 'T11_MALHA_SEM_CADASTRO'
    END;

    INSERT INTO controle.rejeicao (id_lote, linha_origem, regra, detalhe, registro)
    SELECT p_id_lote, t.linha_origem, t.regra, 'Geometria não aproveitada',
           jsonb_build_object('nivel', t.nivel, 'codarea', t.codarea)
    FROM t_malha t WHERE t.regra IS NOT NULL;

    UPDATE core.municipio m SET geom = t.geom
    FROM t_malha t
    WHERE t.regra IS NULL AND t.nivel = 'MUN' AND m.cd_mun = t.codarea
      AND (m.geom IS NULL OR NOT ST_Equals(m.geom, t.geom));

    UPDATE core.uf u SET geom = t.geom
    FROM t_malha t
    WHERE t.regra IS NULL AND t.nivel = 'UF' AND u.cd_uf::text = t.codarea
      AND (u.geom IS NULL OR NOT ST_Equals(u.geom, t.geom));

    SELECT count(*) FILTER (WHERE regra IS NULL), count(*) FILTER (WHERE regra IS NOT NULL)
      INTO aceitas, rejeitadas FROM t_malha;

    UPDATE controle.lote_carga
       SET status = 'PROCESSADO', linhas_lidas = v_lidas, linhas_aceitas = aceitas,
           linhas_rejeitadas = rejeitadas, concluido_em = now()
     WHERE id_lote = p_id_lote;

    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION core.fn_processar_lote_ibge_malha(bigint) IS 'Aplica geometrias de municípios e UFs, corrigindo validade topológica (ST_MakeValid).';

-- ---------------------------------------------------------------------
-- Ocorrências do Atlas Digital de Desastres
-- ---------------------------------------------------------------------
CREATE FUNCTION core.fn_processar_lote_atlas(p_id_lote bigint)
RETURNS TABLE (aceitas integer, rejeitadas integer, ajustadas integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_lidas integer;
BEGIN
    SELECT count(*) INTO v_lidas FROM staging.atlas_ocorrencia WHERE id_lote = p_id_lote;

    -- 1. Interpretação dos campos
    CREATE TEMP TABLE t_oc ON COMMIT DROP AS
    SELECT s.*,
           staging.fn_normalizar_cd_mun(s.cd_mun)            AS cd_mun_n,
           NULL::char(7)                                      AS cd_mun_final,
           false                                              AS mun_ajustado,
           upper(staging.fn_texto(s.protocolo))               AS protocolo_n,
           upper(staging.fn_texto(s.uf))                      AS uf_n,
           staging.fn_normalizar_cobrade(s.cobrade)           AS cobrade_n,
           staging.fn_parse_data(s.dt_evento)                 AS dt_evento_n,
           staging.fn_parse_data(s.dt_registro)               AS dt_registro_n,
           staging.fn_texto(s.situacao)                       AS situacao_n,
           NULL::text                                         AS chave_origem,
           NULL::text                                         AS regra,
           NULL::text                                         AS detalhe
    FROM staging.atlas_ocorrencia s
    WHERE s.id_lote = p_id_lote;

    -- 2. Resolução do município (com ajuste rastreável para código de 6 dígitos)
    UPDATE t_oc t SET cd_mun_final = m.cd_mun
    FROM core.municipio m WHERE length(t.cd_mun_n) = 7 AND m.cd_mun = t.cd_mun_n;

    UPDATE t_oc t SET cd_mun_final = x.cd_mun, mun_ajustado = true
    FROM (SELECT left(cd_mun, 6) AS cd6, min(cd_mun) AS cd_mun
          FROM core.municipio GROUP BY 1 HAVING count(*) = 1) x
    WHERE length(t.cd_mun_n) = 6 AND x.cd6 = t.cd_mun_n;

    UPDATE t_oc SET chave_origem = coalesce(
        protocolo_n,
        'H:' || encode(digest(concat_ws('|', cd_mun_final, cobrade_n, dt_evento_n), 'sha256'), 'hex'));

    -- 3. Regras de qualidade (a primeira violada é registrada)
    UPDATE t_oc t SET regra = r.regra, detalhe = r.detalhe
    FROM (
        SELECT t2.linha_origem,
               CASE
                 WHEN t2.cd_mun_n IS NULL THEN 'R01_MUN_AUSENTE'
                 WHEN t2.cd_mun_final IS NULL THEN 'R02_MUN_INEXISTENTE'
                 WHEN length(t2.uf_n) = 2 AND t2.uf_n <> u.sigla_uf THEN 'R03_UF_DIVERGENTE'
                 WHEN t2.cobrade_n IS NULL OR c.cd_cobrade IS NULL THEN 'R04_COBRADE_INEXISTENTE'
                 WHEN NOT c.classificavel THEN 'R05_COBRADE_NAO_FOLHA'
                 WHEN t2.dt_evento_n IS NULL THEN 'R06_DATA_EVENTO_INVALIDA'
                 WHEN t2.dt_evento_n > current_date THEN 'R07_DATA_EVENTO_FUTURA'
                 WHEN t2.dt_registro_n < t2.dt_evento_n THEN 'R08_REGISTRO_ANTES_DO_EVENTO'
                 WHEN t2.protocolo_n IS NOT NULL AND t2.protocolo_n !~ '^[A-Z0-9][A-Z0-9./-]{3,}$' THEN 'R09_PROTOCOLO_FORMATO'
                 WHEN dn.invalido IS NOT NULL THEN 'R10_DANO_INVALIDO'
               END AS regra,
               CASE
                 WHEN t2.cd_mun_final IS NULL THEN 'Código recebido: ' || coalesce(t2.cd_mun, '(vazio)')
                 WHEN length(t2.uf_n) = 2 AND t2.uf_n <> u.sigla_uf THEN 'UF informada ' || t2.uf_n || ', município pertence a ' || u.sigla_uf
                 WHEN t2.cobrade_n IS NULL OR c.cd_cobrade IS NULL THEN 'COBRADE recebido: ' || coalesce(t2.cobrade, '(vazio)')
                 WHEN NOT c.classificavel THEN 'COBRADE ' || c.cd_cobrade || ' é nível ' || c.nivel || ', não folha'
                 WHEN t2.dt_evento_n IS NULL THEN 'Data recebida: ' || coalesce(t2.dt_evento, '(vazio)')
                 ELSE dn.invalido
               END AS detalhe
        FROM t_oc t2
        LEFT JOIN core.municipio m ON m.cd_mun = t2.cd_mun_final
        LEFT JOIN core.uf u        ON u.cd_uf = m.cd_uf
        LEFT JOIN core.cobrade c   ON c.cd_cobrade = t2.cobrade_n
        LEFT JOIN LATERAL (
            SELECT string_agg(d.key || '=' || d.value, '; ') AS invalido
            FROM jsonb_each_text(t2.danos) d
            JOIN core.indicador_dano i ON i.cd_indicador = d.key
            WHERE staging.fn_texto(d.value) IS NOT NULL
              AND ( staging.fn_parse_numero(d.value) IS NULL
                 OR staging.fn_parse_numero(d.value) < 0
                 OR (i.unidade <> 'BRL' AND staging.fn_parse_numero(d.value) <> trunc(staging.fn_parse_numero(d.value))) )
        ) dn ON true
    ) r
    WHERE r.linha_origem = t.linha_origem AND r.regra IS NOT NULL;

    -- Duplicidade avaliada entre as linhas válidas: mantém a primeira.
    UPDATE t_oc t SET regra = 'R11_DUPLICADO_NO_LOTE',
                      detalhe = 'Mesma chave da linha ' || d.primeira
    FROM (SELECT linha_origem,
                 first_value(linha_origem) OVER w AS primeira,
                 row_number() OVER w AS rn
          FROM t_oc WHERE regra IS NULL
          WINDOW w AS (PARTITION BY chave_origem ORDER BY linha_origem)) d
    WHERE d.linha_origem = t.linha_origem AND d.rn > 1;

    -- 4. Quarentena e ajustes
    INSERT INTO controle.rejeicao (id_lote, linha_origem, regra, detalhe, registro)
    SELECT p_id_lote, s.linha_origem, t.regra, t.detalhe, to_jsonb(s) - 'id_lote'
    FROM t_oc t
    JOIN staging.atlas_ocorrencia s ON s.id_lote = p_id_lote AND s.linha_origem = t.linha_origem
    WHERE t.regra IS NOT NULL;

    INSERT INTO controle.ajuste (id_lote, linha_origem, campo, valor_original, valor_ajustado, regra)
    SELECT p_id_lote, linha_origem, 'cd_mun', cd_mun, cd_mun_final, 'A01_MUN_6_DIGITOS_COMPLETADO'
    FROM t_oc WHERE regra IS NULL AND mun_ajustado;

    -- 5. Upsert das ocorrências (sem gerar versão quando nada mudou)
    INSERT INTO core.ocorrencia (chave_origem, protocolo, cd_mun, cd_cobrade, dt_evento, dt_registro,
                                 situacao, id_lote_origem, linha_origem)
    SELECT chave_origem, protocolo_n, cd_mun_final, cobrade_n, dt_evento_n, dt_registro_n,
           situacao_n, p_id_lote, linha_origem
    FROM t_oc WHERE regra IS NULL
    ON CONFLICT (chave_origem) DO UPDATE
       SET cd_mun = EXCLUDED.cd_mun, cd_cobrade = EXCLUDED.cd_cobrade,
           dt_evento = EXCLUDED.dt_evento, dt_registro = EXCLUDED.dt_registro,
           situacao = EXCLUDED.situacao, id_lote_origem = EXCLUDED.id_lote_origem,
           linha_origem = EXCLUDED.linha_origem
     WHERE (core.ocorrencia.cd_mun, core.ocorrencia.cd_cobrade, core.ocorrencia.dt_evento,
            core.ocorrencia.dt_registro, core.ocorrencia.situacao)
           IS DISTINCT FROM
           (EXCLUDED.cd_mun, EXCLUDED.cd_cobrade, EXCLUDED.dt_evento, EXCLUDED.dt_registro, EXCLUDED.situacao);

    -- 6. Danos: o arquivo é a fotografia completa do registro.
    CREATE TEMP TABLE t_dano ON COMMIT DROP AS
    SELECT o.id_ocorrencia, d.key AS cd_indicador, staging.fn_parse_numero(d.value) AS valor
    FROM t_oc t
    JOIN core.ocorrencia o ON o.chave_origem = t.chave_origem
    CROSS JOIN LATERAL jsonb_each_text(t.danos) d
    JOIN core.indicador_dano i ON i.cd_indicador = d.key
    WHERE t.regra IS NULL AND staging.fn_parse_numero(d.value) IS NOT NULL;

    DELETE FROM core.ocorrencia_dano od
    USING t_oc t JOIN core.ocorrencia o ON o.chave_origem = t.chave_origem
    WHERE t.regra IS NULL AND od.id_ocorrencia = o.id_ocorrencia
      AND NOT EXISTS (SELECT 1 FROM t_dano n WHERE n.id_ocorrencia = od.id_ocorrencia AND n.cd_indicador = od.cd_indicador);

    INSERT INTO core.ocorrencia_dano (id_ocorrencia, cd_indicador, valor)
    SELECT id_ocorrencia, cd_indicador, valor FROM t_dano
    ON CONFLICT (id_ocorrencia, cd_indicador) DO UPDATE
       SET valor = EXCLUDED.valor
     WHERE core.ocorrencia_dano.valor IS DISTINCT FROM EXCLUDED.valor;

    -- 7. Fechamento do lote
    SELECT count(*) FILTER (WHERE regra IS NULL),
           count(*) FILTER (WHERE regra IS NOT NULL),
           count(*) FILTER (WHERE regra IS NULL AND mun_ajustado)
      INTO aceitas, rejeitadas, ajustadas FROM t_oc;

    UPDATE controle.lote_carga
       SET status = 'PROCESSADO', linhas_lidas = v_lidas, linhas_aceitas = aceitas,
           linhas_rejeitadas = rejeitadas, concluido_em = now()
     WHERE id_lote = p_id_lote;

    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION core.fn_processar_lote_atlas(bigint) IS 'Valida, rejeita com motivo, ajusta com rastro e grava ocorrências e danos de um lote do Atlas. Idempotente.';

-- ---------------------------------------------------------------------
-- Áreas de risco
-- ---------------------------------------------------------------------
CREATE FUNCTION risco.fn_processar_lote_areas_risco(p_id_lote bigint)
RETURNS TABLE (aceitas integer, rejeitadas integer)
LANGUAGE plpgsql AS $$
DECLARE
    v_lidas integer;
BEGIN
    SELECT count(*) INTO v_lidas FROM staging.area_risco WHERE id_lote = p_id_lote;

    CREATE TEMP TABLE t_ar ON COMMIT DROP AS
    SELECT s.*,
           staging.fn_geom_poligonal(s.geojson)          AS geom_n,
           staging.fn_normalizar_grau_risco(s.grau_risco) AS grau_n,
           staging.fn_normalizar_cobrade(s.cobrade)       AS cobrade_n,
           staging.fn_normalizar_cd_mun(s.cd_mun)         AS cd_mun_n,
           NULL::text AS regra
    FROM staging.area_risco s WHERE s.id_lote = p_id_lote;

    UPDATE t_ar t SET regra = CASE
        WHEN staging.fn_texto(t.id_externo) IS NULL THEN 'G01_ID_EXTERNO_AUSENTE'
        WHEN t.geom_n IS NULL THEN 'G02_GEOMETRIA_INVALIDA'
        WHEN t.grau_n IS NULL THEN 'G03_GRAU_RISCO_DESCONHECIDO'
        WHEN t.cd_mun_n IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.municipio m WHERE m.cd_mun = t.cd_mun_n) THEN 'G04_MUN_INEXISTENTE'
        WHEN t.cobrade_n IS NOT NULL AND NOT EXISTS (SELECT 1 FROM core.cobrade c WHERE c.cd_cobrade = t.cobrade_n) THEN 'G05_COBRADE_INEXISTENTE'
    END;

    INSERT INTO controle.rejeicao (id_lote, linha_origem, regra, detalhe, registro)
    SELECT p_id_lote, linha_origem, regra, 'Setor de risco não aproveitado',
           to_jsonb(t) - 'geom_n' - 'geojson' - 'regra'
    FROM t_ar t WHERE regra IS NOT NULL;

    INSERT INTO risco.area_risco (fonte, id_externo, cd_mun, tipologia, grau_risco,
                                  cd_cobrade_relacionado, dt_referencia, geom, id_lote_origem)
    SELECT coalesce(staging.fn_texto(fonte), 'NAO_INFORMADA'), staging.fn_texto(id_externo), cd_mun_n,
           coalesce(staging.fn_texto(tipologia), 'NAO_INFORMADA'), grau_n, cobrade_n,
           staging.fn_parse_data(dt_referencia), geom_n, p_id_lote
    FROM t_ar WHERE regra IS NULL
    ON CONFLICT (fonte, id_externo) DO UPDATE
       SET cd_mun = EXCLUDED.cd_mun, tipologia = EXCLUDED.tipologia, grau_risco = EXCLUDED.grau_risco,
           cd_cobrade_relacionado = EXCLUDED.cd_cobrade_relacionado, dt_referencia = EXCLUDED.dt_referencia,
           geom = EXCLUDED.geom, id_lote_origem = EXCLUDED.id_lote_origem;

    SELECT count(*) FILTER (WHERE regra IS NULL), count(*) FILTER (WHERE regra IS NOT NULL)
      INTO aceitas, rejeitadas FROM t_ar;

    UPDATE controle.lote_carga
       SET status = 'PROCESSADO', linhas_lidas = v_lidas, linhas_aceitas = aceitas,
           linhas_rejeitadas = rejeitadas, concluido_em = now()
     WHERE id_lote = p_id_lote;

    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION risco.fn_processar_lote_areas_risco(bigint) IS 'Promove setores de risco do staging, normalizando grau, geometria e município.';
