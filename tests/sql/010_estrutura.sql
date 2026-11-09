-- Testes de estrutura: padrões de modelagem que valem para todo o banco.
\set ON_ERROR_STOP 1
\echo '010 estrutura'

-- Toda tabela dos schemas do projeto tem chave primária.
DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(n.nspname || '.' || c.relname, ', ') INTO v
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r' AND n.nspname IN ('staging','controle','core','hist','risco')
      AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'p');
    ASSERT v IS NULL, 'Tabelas sem PK: ' || v;
END $$;

-- Toda tabela e coluna dos schemas de negócio está documentada (COMMENT).
DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(n.nspname || '.' || c.relname || coalesce('.' || a.attname, ''), ', ') INTO v
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    WHERE c.relkind = 'r' AND n.nspname IN ('controle','core','risco')
      AND (CASE WHEN a.attname IS NULL THEN obj_description(c.oid, 'pg_class')
                ELSE col_description(c.oid, a.attnum) END) IS NULL;
    ASSERT v IS NULL, 'Objetos sem comentário: ' || v;
END $$;

-- Toda FK tem índice que começa pelas colunas da FK (evita varredura em DELETE/JOIN).
DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(k.conrelid::regclass || '(' || k.conname || ')', ', ') INTO v
    FROM pg_constraint k
    JOIN pg_namespace n ON n.oid = (SELECT relnamespace FROM pg_class WHERE oid = k.conrelid)
    WHERE k.contype = 'f' AND n.nspname IN ('controle','core','risco')
      AND k.conname <> 'fk_ocorrencia_cobrade_folha'
      AND NOT EXISTS (
          SELECT 1 FROM pg_index i
          WHERE i.indrelid = k.conrelid
            AND (i.indkey::int2[])[0:array_length(k.conkey, 1) - 1] = k.conkey);
    ASSERT v IS NULL, 'FKs sem índice: ' || v;
END $$;

-- Toda coluna geométrica usa SIRGAS 2000 (4674) e tem índice GiST.
DO $$
DECLARE v text;
BEGIN
    SELECT string_agg(f_table_schema || '.' || f_table_name || '.' || f_geometry_column || ' srid=' || srid, ', ') INTO v
    FROM geometry_columns
    WHERE f_table_schema IN ('core','risco') AND srid <> 4674;
    ASSERT v IS NULL, 'Geometrias fora do SRID 4674: ' || v;

    SELECT string_agg(g.f_table_schema || '.' || g.f_table_name || '.' || g.f_geometry_column, ', ') INTO v
    FROM geometry_columns g
    WHERE g.f_table_schema IN ('core','risco')
      AND NOT EXISTS (
          SELECT 1 FROM pg_index i
          JOIN pg_class ic ON ic.oid = i.indexrelid
          JOIN pg_am am ON am.oid = ic.relam
          JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
          WHERE i.indrelid = (g.f_table_schema || '.' || g.f_table_name)::regclass
            AND am.amname = 'gist' AND a.attname = g.f_geometry_column);
    ASSERT v IS NULL, 'Geometrias sem índice GiST: ' || v;
END $$;

-- hist.<tabela> começa com exatamente as colunas da origem, na mesma ordem e tipo.
DO $$
DECLARE t text; v_origem text; v_hist text;
BEGIN
    FOREACH t IN ARRAY ARRAY['ocorrencia', 'ocorrencia_dano'] LOOP
        SELECT string_agg(column_name || ':' || data_type, ',' ORDER BY ordinal_position) INTO v_origem
        FROM information_schema.columns WHERE table_schema = 'core' AND table_name = t;
        SELECT string_agg(column_name || ':' || data_type, ',' ORDER BY ordinal_position) INTO v_hist
        FROM information_schema.columns WHERE table_schema = 'hist' AND table_name = t AND column_name NOT LIKE 'hist\_%';
        ASSERT v_origem = v_hist, format('hist.%s divergiu de core.%s. Origem: %s | Hist: %s', t, t, v_origem, v_hist);
    END LOOP;
END $$;
