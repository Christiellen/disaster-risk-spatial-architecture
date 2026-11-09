-- Testes unitários das funções de normalização.
\set ON_ERROR_STOP 1
\echo '020 normalizacao'

DO $$
BEGIN
    -- datas
    ASSERT staging.fn_parse_data('15/01/2023')           = DATE '2023-01-15', 'dd/mm/aaaa';
    ASSERT staging.fn_parse_data('2023-01-15')           = DATE '2023-01-15', 'ISO';
    ASSERT staging.fn_parse_data('2023-01-15 00:00:00')  = DATE '2023-01-15', 'ISO com hora';
    ASSERT staging.fn_parse_data('45292')                = DATE '2024-01-01', 'série Excel';
    ASSERT staging.fn_parse_data('45292.0')              = DATE '2024-01-01', 'série Excel com .0';
    ASSERT staging.fn_parse_data('31/02/2020') IS NULL,  'data impossível';
    ASSERT staging.fn_parse_data('ontem') IS NULL,       'texto';
    ASSERT staging.fn_parse_data('  ') IS NULL,          'vazio';

    -- números
    ASSERT staging.fn_parse_numero('1.234,56')       = 1234.56, 'pt-BR';
    ASSERT staging.fn_parse_numero('12.345.678,90')  = 12345678.90, 'pt-BR milhões';
    ASSERT staging.fn_parse_numero('1,234.56')       = 1234.56, 'en-US';
    ASSERT staging.fn_parse_numero('R$ 500,00')      = 500, 'com moeda';
    ASSERT staging.fn_parse_numero('15.432')         = 15432, 'milhar pt-BR (ambiguidade documentada)';
    ASSERT staging.fn_parse_numero('2,5')            = 2.5, 'decimal pt-BR';
    ASSERT staging.fn_parse_numero('120')            = 120, 'inteiro';
    ASSERT staging.fn_parse_numero('-')  IS NULL,    'traço = vazio';
    ASSERT staging.fn_parse_numero('abc') IS NULL,   'texto';

    -- COBRADE
    ASSERT staging.fn_normalizar_cobrade('12100')              = '12100', 'simples';
    ASSERT staging.fn_normalizar_cobrade('1.3.2.1.4')          = '13214', 'pontuado';
    ASSERT staging.fn_normalizar_cobrade('12200 - Enxurradas') = '12200', 'com descrição';
    ASSERT staging.fn_normalizar_cobrade('Inundações') IS NULL, 'só descrição';

    -- município
    ASSERT staging.fn_normalizar_cd_mun('4205407.0') = '4205407', 'float de planilha';
    ASSERT staging.fn_normalizar_cd_mun(' 42.05407 ') = '4205407', 'pontuação';
    ASSERT staging.fn_normalizar_cd_mun('') IS NULL, 'vazio';

    -- grau de risco
    ASSERT staging.fn_normalizar_grau_risco('Muito Alto') = 'MUITO_ALTO', 'textual';
    ASSERT staging.fn_normalizar_grau_risco('médio')      = 'MEDIO', 'acento e caixa';
    ASSERT staging.fn_normalizar_grau_risco('R4')         = 'MUITO_ALTO', 'escala R';
    ASSERT staging.fn_normalizar_grau_risco('Crítico') IS NULL, 'desconhecido';

    -- geometria: laço inválido é corrigido; lixo vira NULL
    ASSERT ST_IsValid(staging.fn_geom_poligonal(
        '{"type":"Polygon","coordinates":[[[0,0],[1,1],[1,0],[0,1],[0,0]]]}')), 'laço corrigido';
    ASSERT staging.fn_geom_poligonal('{"type":"Point","coordinates":[0,0]}') IS NULL, 'ponto não é polígono';
    ASSERT staging.fn_geom_poligonal('não é json') IS NULL, 'texto inválido';
END $$;
