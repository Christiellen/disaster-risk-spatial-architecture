-- =====================================================================
-- V4 - Classificação COBRADE e catálogo de indicadores de dano
--
-- COBRADE (Classificação e Codificação Brasileira de Desastres) é
-- hierárquica: categoria > grupo > subgrupo > tipo > subtipo.
-- O código de 5 dígitos é a concatenação dos níveis (1.1.3.2.1 -> 11321).
-- Modelada como árvore autorreferenciada (ver ADR-0004).
--
-- ATENÇÃO: a carga inicial cobre a categoria NATURAL e foi transcrita
-- para fins de portfólio. Deve ser conferida contra o anexo oficial
-- vigente antes de qualquer uso real. A categoria TECNOLÓGICO está
-- registrada apenas no nível raiz (pendência P-01).
-- =====================================================================

CREATE TABLE core.cobrade (
    cd_cobrade    char(5)  PRIMARY KEY CHECK (cd_cobrade ~ '^[12][0-9]{4}$'),
    nivel         text     NOT NULL CHECK (nivel IN ('CATEGORIA', 'GRUPO', 'SUBGRUPO', 'TIPO', 'SUBTIPO')),
    cd_pai        char(5)  REFERENCES core.cobrade (cd_cobrade),
    descricao     text     NOT NULL,
    classificavel boolean  NOT NULL,
    ativo         boolean  NOT NULL DEFAULT true,
    CONSTRAINT uq_cobrade_classificavel UNIQUE (cd_cobrade, classificavel),
    CONSTRAINT ck_cobrade_raiz CHECK ((nivel = 'CATEGORIA') = (cd_pai IS NULL)),
    CONSTRAINT ck_cobrade_categoria_prefixo CHECK (cd_pai IS NULL OR left(cd_pai, 1) = left(cd_cobrade, 1))
);

CREATE INDEX ix_cobrade_pai ON core.cobrade (cd_pai);

COMMENT ON TABLE  core.cobrade IS 'Árvore da Classificação e Codificação Brasileira de Desastres (COBRADE).';
COMMENT ON COLUMN core.cobrade.cd_cobrade IS 'Código de 5 dígitos (categoria, grupo, subgrupo, tipo, subtipo).';
COMMENT ON COLUMN core.cobrade.nivel IS 'Nível do nó na hierarquia.';
COMMENT ON COLUMN core.cobrade.cd_pai IS 'Nó imediatamente superior. Nulo apenas para CATEGORIA.';
COMMENT ON COLUMN core.cobrade.descricao IS 'Descrição oficial da tipologia.';
COMMENT ON COLUMN core.cobrade.classificavel IS 'Verdadeiro para nós-folha, os únicos aceitos na classificação de uma ocorrência.';
COMMENT ON COLUMN core.cobrade.ativo IS 'Permite descontinuar códigos sem apagar o histórico que os referencia.';

INSERT INTO core.cobrade (cd_cobrade, nivel, cd_pai, descricao, classificavel) VALUES
 ('10000','CATEGORIA',NULL,   'Natural', false),
 ('20000','CATEGORIA',NULL,   'Tecnológico', false),
 -- Geológico
 ('11000','GRUPO',   '10000','Geológico', false),
 ('11100','SUBGRUPO','11000','Terremoto', false),
 ('11110','TIPO',    '11100','Tremor de terra', true),
 ('11120','TIPO',    '11100','Tsunami', true),
 ('11200','SUBGRUPO','11000','Emanação vulcânica', true),
 ('11300','SUBGRUPO','11000','Movimento de massa', false),
 ('11310','TIPO',    '11300','Quedas, tombamentos e rolamentos', false),
 ('11311','SUBTIPO', '11310','Blocos', true),
 ('11312','SUBTIPO', '11310','Lascas', true),
 ('11313','SUBTIPO', '11310','Matacões', true),
 ('11314','SUBTIPO', '11310','Lajes', true),
 ('11320','TIPO',    '11300','Deslizamentos', false),
 ('11321','SUBTIPO', '11320','Deslizamentos de solo e/ou rocha', true),
 ('11330','TIPO',    '11300','Corridas de massa', false),
 ('11331','SUBTIPO', '11330','Solo/lama', true),
 ('11332','SUBTIPO', '11330','Rocha/detrito', true),
 ('11340','TIPO',    '11300','Subsidências e colapsos', true),
 ('11400','SUBGRUPO','11000','Erosão', false),
 ('11410','TIPO',    '11400','Erosão costeira/marinha', true),
 ('11420','TIPO',    '11400','Erosão de margem fluvial', true),
 ('11430','TIPO',    '11400','Erosão continental', false),
 ('11431','SUBTIPO', '11430','Laminar', true),
 ('11432','SUBTIPO', '11430','Ravinas', true),
 ('11433','SUBTIPO', '11430','Boçorocas', true),
 -- Hidrológico
 ('12000','GRUPO',   '10000','Hidrológico', false),
 ('12100','SUBGRUPO','12000','Inundações', true),
 ('12200','SUBGRUPO','12000','Enxurradas', true),
 ('12300','SUBGRUPO','12000','Alagamentos', true),
 -- Meteorológico
 ('13000','GRUPO',   '10000','Meteorológico', false),
 ('13100','SUBGRUPO','13000','Sistemas de grande escala/escala regional', false),
 ('13110','TIPO',    '13100','Ciclones', false),
 ('13111','SUBTIPO', '13110','Ventos costeiros (mobilidade de dunas)', true),
 ('13112','SUBTIPO', '13110','Marés de tempestade (ressacas)', true),
 ('13120','TIPO',    '13100','Frentes frias/zonas de convergência', true),
 ('13200','SUBGRUPO','13000','Tempestades', false),
 ('13210','TIPO',    '13200','Tempestade local/convectiva', false),
 ('13211','SUBTIPO', '13210','Tornados', true),
 ('13212','SUBTIPO', '13210','Tempestade de raios', true),
 ('13213','SUBTIPO', '13210','Granizo', true),
 ('13214','SUBTIPO', '13210','Chuvas intensas', true),
 ('13215','SUBTIPO', '13210','Vendaval', true),
 ('13300','SUBGRUPO','13000','Temperaturas extremas', false),
 ('13310','TIPO',    '13300','Onda de calor', true),
 ('13320','TIPO',    '13300','Onda de frio', false),
 ('13321','SUBTIPO', '13320','Friagem', true),
 ('13322','SUBTIPO', '13320','Geadas', true),
 -- Climatológico
 ('14000','GRUPO',   '10000','Climatológico', false),
 ('14100','SUBGRUPO','14000','Seca', false),
 ('14110','TIPO',    '14100','Estiagem', true),
 ('14120','TIPO',    '14100','Seca', true),
 ('14130','TIPO',    '14100','Incêndio florestal', false),
 ('14131','SUBTIPO', '14130','Incêndios em áreas protegidas', true),
 ('14132','SUBTIPO', '14130','Incêndios em áreas não protegidas', true),
 ('14140','TIPO',    '14100','Baixa umidade do ar', true),
 -- Biológico
 ('15000','GRUPO',   '10000','Biológico', false),
 ('15100','SUBGRUPO','15000','Epidemias', false),
 ('15110','TIPO',    '15100','Doenças infecciosas virais', true),
 ('15120','TIPO',    '15100','Doenças infecciosas bacterianas', true),
 ('15130','TIPO',    '15100','Doenças infecciosas parasíticas', true),
 ('15140','TIPO',    '15100','Doenças infecciosas fúngicas', true),
 ('15200','SUBGRUPO','15000','Infestações/pragas', false),
 ('15210','TIPO',    '15200','Infestações de animais', true),
 ('15220','TIPO',    '15200','Infestações de algas', false),
 ('15221','SUBTIPO', '15220','Marés vermelhas', true),
 ('15222','SUBTIPO', '15220','Cianobactérias em reservatórios', true),
 ('15230','TIPO',    '15200','Outras infestações', true);

-- Visão achatada: cada folha com o caminho completo até a categoria.
CREATE VIEW core.vw_cobrade_hierarquia AS
WITH RECURSIVE arvore AS (
    SELECT c.cd_cobrade, c.cd_cobrade AS cd_ancestral, c.nivel AS nivel_ancestral, c.descricao AS desc_ancestral, 0 AS profundidade
    FROM core.cobrade c
    UNION ALL
    SELECT a.cd_cobrade, p.cd_cobrade, p.nivel, p.descricao, a.profundidade + 1
    FROM arvore a
    JOIN core.cobrade f ON f.cd_cobrade = a.cd_ancestral
    JOIN core.cobrade p ON p.cd_cobrade = f.cd_pai
)
SELECT c.cd_cobrade,
       c.descricao,
       c.nivel,
       c.classificavel,
       max(a.desc_ancestral) FILTER (WHERE a.nivel_ancestral = 'CATEGORIA') AS categoria,
       max(a.desc_ancestral) FILTER (WHERE a.nivel_ancestral = 'GRUPO')     AS grupo,
       max(a.desc_ancestral) FILTER (WHERE a.nivel_ancestral = 'SUBGRUPO')  AS subgrupo,
       max(a.desc_ancestral) FILTER (WHERE a.nivel_ancestral = 'TIPO')      AS tipo,
       max(a.desc_ancestral) FILTER (WHERE a.nivel_ancestral = 'SUBTIPO')   AS subtipo
FROM core.cobrade c
JOIN arvore a ON a.cd_cobrade = c.cd_cobrade
GROUP BY c.cd_cobrade, c.descricao, c.nivel, c.classificavel;

COMMENT ON VIEW core.vw_cobrade_hierarquia IS 'COBRADE achatada: cada código com a descrição de todos os seus ancestrais.';

-- ---------------------------------------------------------------------
-- Catálogo de indicadores de dano/prejuízo
-- ---------------------------------------------------------------------
CREATE TABLE core.indicador_dano (
    cd_indicador text PRIMARY KEY CHECK (cd_indicador ~ '^[A-Z][A-Z0-9_]+$'),
    categoria    text NOT NULL CHECK (categoria IN ('HUMANO', 'MATERIAL', 'PREJUIZO_PUBLICO', 'PREJUIZO_PRIVADO')),
    unidade      text NOT NULL CHECK (unidade IN ('PESSOAS', 'UNIDADES', 'BRL')),
    descricao    text NOT NULL,
    compoe_total_humano boolean NOT NULL DEFAULT false,
    CONSTRAINT ck_indicador_total_humano CHECK (NOT compoe_total_humano OR categoria = 'HUMANO')
);

COMMENT ON TABLE  core.indicador_dano IS 'Catálogo dos indicadores de dano e prejuízo registrados por ocorrência (modelo longo, ver ADR-0005).';
COMMENT ON COLUMN core.indicador_dano.cd_indicador IS 'Código do indicador.';
COMMENT ON COLUMN core.indicador_dano.categoria IS 'Categoria do dano.';
COMMENT ON COLUMN core.indicador_dano.unidade IS 'Unidade de medida do valor.';
COMMENT ON COLUMN core.indicador_dano.descricao IS 'Descrição do indicador.';
COMMENT ON COLUMN core.indicador_dano.compoe_total_humano IS 'Se o indicador entra no total de pessoas diretamente afetadas (calculado, nunca armazenado).';

INSERT INTO core.indicador_dano (cd_indicador, categoria, unidade, descricao, compoe_total_humano) VALUES
 ('DH_MORTOS',          'HUMANO',  'PESSOAS',  'Óbitos', true),
 ('DH_FERIDOS',         'HUMANO',  'PESSOAS',  'Feridos', true),
 ('DH_ENFERMOS',        'HUMANO',  'PESSOAS',  'Enfermos', true),
 ('DH_DESABRIGADOS',    'HUMANO',  'PESSOAS',  'Desabrigados (necessitam de abrigo público)', true),
 ('DH_DESALOJADOS',     'HUMANO',  'PESSOAS',  'Desalojados (deixaram a residência sem necessitar de abrigo público)', true),
 ('DH_DESAPARECIDOS',   'HUMANO',  'PESSOAS',  'Desaparecidos', true),
 ('DH_OUTROS_AFETADOS', 'HUMANO',  'PESSOAS',  'Outros afetados', false),
 ('DM_UH_DANIFICADAS',  'MATERIAL','UNIDADES', 'Unidades habitacionais danificadas', false),
 ('DM_UH_DESTRUIDAS',   'MATERIAL','UNIDADES', 'Unidades habitacionais destruídas', false),
 ('DM_VALOR_TOTAL',     'MATERIAL','BRL',      'Valor total dos danos materiais', false),
 ('PEPL_TOTAL',         'PREJUIZO_PUBLICO', 'BRL', 'Prejuízo econômico público total', false),
 ('PEPR_TOTAL',         'PREJUIZO_PRIVADO', 'BRL', 'Prejuízo econômico privado total', false);
