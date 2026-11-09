-- =====================================================================
-- V3 - Território (UF e município)
-- SRID 4674 = SIRGAS 2000, referencial geodésico oficial do Brasil e
-- o mesmo das malhas do IBGE (ver ADR-0003).
-- =====================================================================

CREATE TABLE core.regiao (
    sigla_regiao char(2) PRIMARY KEY CHECK (sigla_regiao IN ('N', 'NE', 'SE', 'S', 'CO')),
    nome         text    NOT NULL UNIQUE
);

COMMENT ON TABLE  core.regiao IS 'Grandes regiões do IBGE.';
COMMENT ON COLUMN core.regiao.sigla_regiao IS 'Sigla da região (N, NE, SE, S, CO).';
COMMENT ON COLUMN core.regiao.nome IS 'Nome da região.';

INSERT INTO core.regiao (sigla_regiao, nome) VALUES
    ('N', 'Norte'), ('NE', 'Nordeste'), ('SE', 'Sudeste'), ('S', 'Sul'), ('CO', 'Centro-Oeste');

CREATE TABLE core.uf (
    cd_uf        smallint PRIMARY KEY CHECK (cd_uf BETWEEN 11 AND 53),
    sigla_uf     char(2)  NOT NULL UNIQUE CHECK (sigla_uf ~ '^[A-Z]{2}$'),
    nome         text     NOT NULL UNIQUE,
    sigla_regiao char(2)  NOT NULL REFERENCES core.regiao (sigla_regiao),
    geom         geometry(MultiPolygon, 4674),
    CONSTRAINT ck_uf_geom_valida CHECK (geom IS NULL OR ST_IsValid(geom)),
    CONSTRAINT ck_uf_regiao_coerente CHECK (
        (cd_uf / 10 = 1 AND sigla_regiao = 'N')  OR
        (cd_uf / 10 = 2 AND sigla_regiao = 'NE') OR
        (cd_uf / 10 = 3 AND sigla_regiao = 'SE') OR
        (cd_uf / 10 = 4 AND sigla_regiao = 'S')  OR
        (cd_uf / 10 = 5 AND sigla_regiao = 'CO')
    )
);

CREATE INDEX gx_uf_geom ON core.uf USING gist (geom);
CREATE INDEX ix_uf_regiao ON core.uf (sigla_regiao);

COMMENT ON TABLE  core.uf IS 'Unidades da Federação.';
COMMENT ON COLUMN core.uf.cd_uf IS 'Código IBGE da UF (2 dígitos). O primeiro dígito identifica a região.';
COMMENT ON COLUMN core.uf.sigla_uf IS 'Sigla da UF.';
COMMENT ON COLUMN core.uf.nome IS 'Nome da UF.';
COMMENT ON COLUMN core.uf.sigla_regiao IS 'Região da UF. Coerência com o primeiro dígito do código é garantida por CHECK.';
COMMENT ON COLUMN core.uf.geom IS 'Limite da UF (SIRGAS 2000). Opcional: o modelo funciona sem geometria.';

CREATE TABLE core.municipio (
    cd_mun      char(7)  PRIMARY KEY CHECK (cd_mun ~ '^[0-9]{7}$'),
    cd_uf       smallint NOT NULL REFERENCES core.uf (cd_uf),
    nome        text     NOT NULL,
    geom        geometry(MultiPolygon, 4674),
    area_km2    numeric(12, 3) GENERATED ALWAYS AS (
                    round((ST_Area(geom::geography) / 1e6)::numeric, 3)
                ) STORED,
    ponto_ref   geometry(Point, 4674) GENERATED ALWAYS AS (ST_PointOnSurface(geom)) STORED,
    CONSTRAINT ck_mun_prefixo_uf CHECK (substr(cd_mun, 1, 2)::smallint = cd_uf),
    CONSTRAINT ck_mun_geom_valida CHECK (geom IS NULL OR ST_IsValid(geom))
);

CREATE INDEX gx_municipio_geom      ON core.municipio USING gist (geom);
CREATE INDEX gx_municipio_ponto_ref ON core.municipio USING gist (ponto_ref);
CREATE INDEX gx_municipio_ponto_geog ON core.municipio USING gist ((ponto_ref::geography));
CREATE INDEX ix_municipio_uf        ON core.municipio (cd_uf);

COMMENT ON TABLE  core.municipio IS 'Municípios brasileiros conforme código e malha do IBGE.';
COMMENT ON COLUMN core.municipio.cd_mun IS 'Código IBGE do município (7 dígitos; os 2 primeiros são a UF).';
COMMENT ON COLUMN core.municipio.cd_uf IS 'UF do município. Deve coincidir com o prefixo do código (CHECK).';
COMMENT ON COLUMN core.municipio.nome IS 'Nome oficial do município.';
COMMENT ON COLUMN core.municipio.geom IS 'Limite municipal (SIRGAS 2000). Opcional.';
COMMENT ON COLUMN core.municipio.area_km2 IS 'Área geodésica em km², calculada a partir da geometria (coluna gerada).';
COMMENT ON COLUMN core.municipio.ponto_ref IS 'Ponto garantidamente interno ao polígono (ST_PointOnSurface), usado em consultas por raio e no app mobile.';
