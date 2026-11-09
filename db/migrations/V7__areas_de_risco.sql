-- =====================================================================
-- V7 - Áreas de risco (camada geoespacial)
-- Estrutura genérica para setores de risco geológico/hidrológico,
-- como a setorização do Serviço Geológico do Brasil (SGB).
-- =====================================================================

CREATE TABLE risco.area_risco (
    id_area        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fonte          text        NOT NULL,
    id_externo     text        NOT NULL,
    cd_mun         char(7)     REFERENCES core.municipio (cd_mun),
    tipologia      text        NOT NULL,
    grau_risco     text        NOT NULL CHECK (grau_risco IN ('BAIXO', 'MEDIO', 'ALTO', 'MUITO_ALTO')),
    cd_cobrade_relacionado char(5) REFERENCES core.cobrade (cd_cobrade),
    dt_referencia  date,
    geom           geometry(MultiPolygon, 4674) NOT NULL,
    id_lote_origem bigint      NOT NULL REFERENCES controle.lote_carga (id_lote),
    CONSTRAINT uq_area_risco_origem UNIQUE (fonte, id_externo),
    CONSTRAINT ck_area_risco_geom_valida CHECK (ST_IsValid(geom)),
    CONSTRAINT ck_area_risco_geom_nao_vazia CHECK (NOT ST_IsEmpty(geom))
);

CREATE INDEX gx_area_risco_geom ON risco.area_risco USING gist (geom);
CREATE INDEX ix_area_risco_mun  ON risco.area_risco (cd_mun);
CREATE INDEX ix_area_risco_cobrade ON risco.area_risco (cd_cobrade_relacionado);
CREATE INDEX ix_area_risco_lote ON risco.area_risco (id_lote_origem);

COMMENT ON TABLE  risco.area_risco IS 'Setores de risco mapeados (polígonos), associados ao município e opcionalmente a uma tipologia COBRADE.';
COMMENT ON COLUMN risco.area_risco.id_area IS 'Chave substituta.';
COMMENT ON COLUMN risco.area_risco.fonte IS 'Instituição/produto de origem (ex.: SGB_SETORIZACAO).';
COMMENT ON COLUMN risco.area_risco.id_externo IS 'Identificador do setor na fonte. Com a fonte, forma a chave natural.';
COMMENT ON COLUMN risco.area_risco.cd_mun IS 'Município do setor. Preenchido pela fonte ou, se ausente, por interseção espacial.';
COMMENT ON COLUMN risco.area_risco.tipologia IS 'Tipologia de processo descrita pela fonte (ex.: deslizamento, inundação).';
COMMENT ON COLUMN risco.area_risco.grau_risco IS 'Grau de risco normalizado.';
COMMENT ON COLUMN risco.area_risco.cd_cobrade_relacionado IS 'Código COBRADE equivalente, quando a correspondência é inequívoca.';
COMMENT ON COLUMN risco.area_risco.dt_referencia IS 'Data de referência do mapeamento.';
COMMENT ON COLUMN risco.area_risco.geom IS 'Polígono do setor (SIRGAS 2000). Válido e não vazio.';
COMMENT ON COLUMN risco.area_risco.id_lote_origem IS 'Lote de carga de origem.';

-- Município ausente: deriva pela maior sobreposição com a malha municipal.
CREATE FUNCTION risco.fn_inferir_municipio() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.cd_mun IS NULL THEN
        SELECT m.cd_mun INTO NEW.cd_mun
        FROM core.municipio m
        WHERE m.geom && NEW.geom AND ST_Intersects(m.geom, NEW.geom)
        ORDER BY ST_Area(ST_Intersection(m.geom, NEW.geom)) DESC
        LIMIT 1;
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION risco.fn_inferir_municipio() IS 'Preenche o município do setor de risco pela maior área de interseção, quando a fonte não informa.';

CREATE TRIGGER tg_area_risco_municipio
    BEFORE INSERT OR UPDATE OF geom, cd_mun ON risco.area_risco
    FOR EACH ROW EXECUTE FUNCTION risco.fn_inferir_municipio();
