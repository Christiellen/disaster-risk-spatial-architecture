-- =====================================================================
-- V8 - Staging e funções de normalização
-- Staging recebe tudo como texto: nenhuma linha é perdida por erro de
-- tipo na leitura. A tipagem e as regras acontecem na promoção para o
-- core (V9), onde cada falha vira uma rejeição rastreável.
-- =====================================================================

CREATE TABLE staging.atlas_ocorrencia (
    id_lote      bigint  NOT NULL REFERENCES controle.lote_carga (id_lote) ON DELETE CASCADE,
    linha_origem integer NOT NULL,
    protocolo    text,
    uf           text,
    cd_mun       text,
    nome_mun     text,
    dt_evento    text,
    dt_registro  text,
    cobrade      text,
    cobrade_desc text,
    situacao     text,
    danos        jsonb   NOT NULL DEFAULT '{}'::jsonb,
    extras       jsonb   NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (id_lote, linha_origem)
);

COMMENT ON TABLE  staging.atlas_ocorrencia IS 'Linhas do arquivo do Atlas Digital de Desastres, com colunas já mapeadas para nomes canônicos (etl/config/atlas_colunas.yaml), ainda sem tipagem.';
COMMENT ON COLUMN staging.atlas_ocorrencia.id_lote IS 'Lote de carga.';
COMMENT ON COLUMN staging.atlas_ocorrencia.linha_origem IS 'Linha no arquivo (1 = primeira linha de dados).';
COMMENT ON COLUMN staging.atlas_ocorrencia.protocolo IS 'Protocolo S2iD, como recebido.';
COMMENT ON COLUMN staging.atlas_ocorrencia.uf IS 'UF, como recebida.';
COMMENT ON COLUMN staging.atlas_ocorrencia.cd_mun IS 'Código IBGE do município, como recebido.';
COMMENT ON COLUMN staging.atlas_ocorrencia.nome_mun IS 'Nome do município, como recebido (apenas conferência).';
COMMENT ON COLUMN staging.atlas_ocorrencia.dt_evento IS 'Data do evento, como recebida.';
COMMENT ON COLUMN staging.atlas_ocorrencia.dt_registro IS 'Data de registro, como recebida.';
COMMENT ON COLUMN staging.atlas_ocorrencia.cobrade IS 'Código COBRADE, como recebido.';
COMMENT ON COLUMN staging.atlas_ocorrencia.cobrade_desc IS 'Descrição da tipologia, como recebida (apenas conferência).';
COMMENT ON COLUMN staging.atlas_ocorrencia.situacao IS 'Situação do registro, como recebida.';
COMMENT ON COLUMN staging.atlas_ocorrencia.danos IS 'Valores de dano como recebidos, indexados pelo código do indicador.';
COMMENT ON COLUMN staging.atlas_ocorrencia.extras IS 'Colunas do arquivo sem mapeamento canônico, preservadas integralmente.';

CREATE TABLE staging.ibge_municipio (
    id_lote      bigint  NOT NULL REFERENCES controle.lote_carga (id_lote) ON DELETE CASCADE,
    linha_origem integer NOT NULL,
    cd_mun       text,
    nome_mun     text,
    cd_uf        text,
    sigla_uf     text,
    nome_uf      text,
    sigla_regiao text,
    PRIMARY KEY (id_lote, linha_origem)
);

COMMENT ON TABLE staging.ibge_municipio IS 'Cadastro de municípios da API de Localidades do IBGE (visão nivelada).';

CREATE TABLE staging.ibge_malha (
    id_lote      bigint  NOT NULL REFERENCES controle.lote_carga (id_lote) ON DELETE CASCADE,
    linha_origem integer NOT NULL,
    nivel        text    NOT NULL CHECK (nivel IN ('MUN', 'UF')),
    codarea      text,
    geojson      text,
    PRIMARY KEY (id_lote, linha_origem)
);

COMMENT ON TABLE staging.ibge_malha IS 'Geometrias da API de Malhas do IBGE, uma feição por linha, em GeoJSON.';

CREATE TABLE staging.area_risco (
    id_lote      bigint  NOT NULL REFERENCES controle.lote_carga (id_lote) ON DELETE CASCADE,
    linha_origem integer NOT NULL,
    fonte        text,
    id_externo   text,
    cd_mun       text,
    tipologia    text,
    grau_risco   text,
    cobrade      text,
    dt_referencia text,
    geojson      text,
    PRIMARY KEY (id_lote, linha_origem)
);

COMMENT ON TABLE staging.area_risco IS 'Setores de risco recebidos em GeoJSON, antes da normalização.';

CREATE TABLE controle.ajuste (
    id_ajuste      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_lote        bigint NOT NULL REFERENCES controle.lote_carga (id_lote) ON DELETE CASCADE,
    linha_origem   integer NOT NULL,
    campo          text   NOT NULL,
    valor_original text,
    valor_ajustado text   NOT NULL,
    regra          text   NOT NULL
);

CREATE INDEX ix_ajuste_lote ON controle.ajuste (id_lote);

COMMENT ON TABLE  controle.ajuste IS 'Correções automáticas aplicadas durante a carga. Nenhum valor é alterado sem deixar registro.';
COMMENT ON COLUMN controle.ajuste.campo IS 'Campo ajustado.';
COMMENT ON COLUMN controle.ajuste.valor_original IS 'Valor recebido.';
COMMENT ON COLUMN controle.ajuste.valor_ajustado IS 'Valor gravado no core.';
COMMENT ON COLUMN controle.ajuste.regra IS 'Regra que justificou o ajuste.';
COMMENT ON COLUMN controle.ajuste.id_ajuste IS 'Identificador do ajuste.';
COMMENT ON COLUMN controle.ajuste.id_lote IS 'Lote em que o ajuste foi aplicado.';
COMMENT ON COLUMN controle.ajuste.linha_origem IS 'Linha do arquivo de origem.';

-- ---------------------------------------------------------------------
-- Funções de normalização (puras, retornam NULL quando não interpretam)
-- ---------------------------------------------------------------------

CREATE FUNCTION staging.fn_texto(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN btrim(p) IN ('', '-', 'NA', 'N/A', 'NULL', 'null', 'nan', 'NaN', 'None') THEN NULL
                ELSE regexp_replace(btrim(p), '\s+', ' ', 'g') END;
$$;
COMMENT ON FUNCTION staging.fn_texto(text) IS 'Apara espaços e converte marcadores de vazio comuns (NA, -, nan) em NULL.';

CREATE FUNCTION staging.fn_parse_data(p text) RETURNS date
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    v text := staging.fn_texto(p);
BEGIN
    IF v IS NULL THEN
        RETURN NULL;
    ELSIF v ~ '^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}(:\d{2})?(\.\d+)?)?$' THEN
        RETURN to_date(left(v, 10), 'YYYY-MM-DD');
    ELSIF v ~ '^\d{2}/\d{2}/\d{4}( \d{2}:\d{2}(:\d{2})?)?$' THEN
        RETURN to_date(left(v, 10), 'DD/MM/YYYY');
    ELSIF v ~ '^\d{4,5}(\.0+)?$' AND split_part(v, '.', 1)::int BETWEEN 1 AND 80000 THEN
        -- número de série de data do Excel (base 1899-12-30)
        RETURN DATE '1899-12-30' + split_part(v, '.', 1)::int;
    END IF;
    RETURN NULL;
EXCEPTION WHEN others THEN
    RETURN NULL;   -- ex.: 31/02/2020
END;
$$;
COMMENT ON FUNCTION staging.fn_parse_data(text) IS 'Interpreta datas em ISO, dd/mm/aaaa ou série do Excel. Datas impossíveis retornam NULL.';

CREATE FUNCTION staging.fn_parse_numero(p text) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    v text := replace(replace(coalesce(staging.fn_texto(p), ''), 'R$', ''), ' ', '');
BEGIN
    IF v = '' THEN
        RETURN NULL;
    ELSIF v ~ '^-?\d{1,3}(\.\d{3})+(,\d+)?$' OR v ~ '^-?\d+,\d+$' THEN
        RETURN replace(replace(v, '.', ''), ',', '.')::numeric;     -- 1.234,56
    ELSIF v ~ '^-?\d{1,3}(,\d{3})+(\.\d+)?$' THEN
        RETURN replace(v, ',', '')::numeric;                         -- 1,234.56
    ELSIF v ~ '^-?\d+(\.\d+)?$' THEN
        RETURN v::numeric;                                           -- 1234.56
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION staging.fn_parse_numero(text) IS 'Interpreta números no padrão brasileiro (1.234,56), americano (1,234.56) ou simples. Retorna NULL se não reconhecer.';

CREATE FUNCTION staging.fn_normalizar_cobrade(p text) RETURNS char(5)
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT replace((regexp_match(coalesce(p, ''), '[12](?:\.?[0-9]){4}'))[1], '.', '')::char(5);
$$;
COMMENT ON FUNCTION staging.fn_normalizar_cobrade(text) IS 'Extrai o código COBRADE de 5 dígitos de formatos como 12100, 1.2.1.0.0 ou "12100 - Inundações".';

CREATE FUNCTION staging.fn_normalizar_cd_mun(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT nullif(regexp_replace(regexp_replace(coalesce(btrim(p), ''), '\.0+$', ''), '\D', '', 'g'), '');
$$;
COMMENT ON FUNCTION staging.fn_normalizar_cd_mun(text) IS 'Mantém apenas dígitos do código do município (remove ".0" de planilhas). Não completa nem corrige.';

CREATE FUNCTION staging.fn_normalizar_grau_risco(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE upper(translate(btrim(coalesce(p, '')), 'áéíóúâêôãõçÁÉÍÓÚÂÊÔÃÕÇ', 'aeiouaeoaocAEIOUAEOAOC'))
               WHEN 'MUITO ALTO' THEN 'MUITO_ALTO' WHEN 'MUITO_ALTO' THEN 'MUITO_ALTO' WHEN 'R4' THEN 'MUITO_ALTO'
               WHEN 'ALTO'  THEN 'ALTO'  WHEN 'R3' THEN 'ALTO'
               WHEN 'MEDIO' THEN 'MEDIO' WHEN 'R2' THEN 'MEDIO'
               WHEN 'BAIXO' THEN 'BAIXO' WHEN 'R1' THEN 'BAIXO'
           END;
$$;
COMMENT ON FUNCTION staging.fn_normalizar_grau_risco(text) IS 'Normaliza graus de risco textuais (Muito Alto, Médio...) ou na escala R1 a R4.';

CREATE FUNCTION staging.fn_geom_poligonal(p_geojson text) RETURNS geometry(MultiPolygon, 4674)
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    g geometry;
BEGIN
    IF p_geojson IS NULL OR btrim(p_geojson) = '' THEN
        RETURN NULL;
    END IF;
    g := ST_SetSRID(ST_GeomFromGeoJSON(p_geojson), 4674);
    g := ST_CollectionExtract(ST_MakeValid(g), 3);
    IF g IS NULL OR ST_IsEmpty(g) THEN
        RETURN NULL;
    END IF;
    RETURN ST_Multi(g)::geometry(MultiPolygon, 4674);
EXCEPTION WHEN others THEN
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION staging.fn_geom_poligonal(text) IS 'Converte GeoJSON em MultiPolygon SIRGAS 2000 válido (ST_MakeValid + extração das partes poligonais). NULL se inválido ou vazio.';
