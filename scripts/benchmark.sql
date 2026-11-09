-- =====================================================================
-- Benchmark de índices - executar com: psql -f scripts/benchmark.sql
--
-- Gera volume sintético comparável ao Brasil real (~5.600 municípios em
-- grade, 200 mil ocorrências), mede consultas com e sem os índices e
-- DESFAZ TUDO ao final (ROLLBACK): o banco não é alterado.
-- O PostgreSQL permite DROP INDEX dentro de transação, o que torna a
-- comparação "sem índice" segura e reversível.
-- =====================================================================
\set ON_ERROR_STOP 1
\timing off
BEGIN;

SET LOCAL client_min_messages = warning;
SET LOCAL max_parallel_workers_per_gather = 0;   -- resultados comparáveis entre máquinas
SET LOCAL jit = off;

-- Lote técnico para o volume sintético
INSERT INTO controle.lote_carga (fonte, arquivo, hash_sha256, status, linhas_lidas, linhas_aceitas, linhas_rejeitadas)
VALUES ('AMOSTRA', 'benchmark', repeat('0', 64), 'PROCESSADO', 200000, 200000, 0)
ON CONFLICT (fonte, hash_sha256) DO NOTHING;

-- UF de testes e grade de 75 x 75 "municípios" de 0,1° (≈ 11 km)
INSERT INTO core.uf (cd_uf, sigla_uf, nome, sigla_regiao)
VALUES (52, 'ZZ', 'UF sintética de benchmark', 'CO')
ON CONFLICT (cd_uf) DO NOTHING;

INSERT INTO core.municipio (cd_mun, cd_uf, nome, geom)
SELECT '52' || lpad((50000 + i * 75 + j)::text, 5, '0'), 52, 'Bench ' || i || '-' || j,
       ST_Multi(ST_MakeEnvelope(-55 + j * 0.1, -20 + i * 0.1, -55 + (j + 1) * 0.1, -20 + (i + 1) * 0.1, 4674))
FROM generate_series(0, 74) i, generate_series(0, 74) j;

-- 200 mil ocorrências distribuídas entre municípios, tipologias e 1991-2025
INSERT INTO core.ocorrencia (chave_origem, cd_mun, cd_cobrade, dt_evento, id_lote_origem, linha_origem)
SELECT 'BENCH-' || n,
       '52' || lpad((50000 + (n * 7919) % 5625)::text, 5, '0'),
       (ARRAY['12100','12200','12300','13214','13215','14110','14120','11321'])[1 + n % 8],
       DATE '1991-01-01' + (n * 37) % 12784,
       (SELECT id_lote FROM controle.lote_carga WHERE arquivo = 'benchmark'),
       n
FROM generate_series(1, 200000) n;

ANALYZE core.municipio;
ANALYZE core.ocorrencia;

\echo
\echo '=== C1. Ocorrências de inundação em um período (B-tree composto cd_cobrade, dt_evento) ==='
\echo '--- com índice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT count(*) FROM core.ocorrencia WHERE cd_cobrade = '12100' AND dt_evento BETWEEN '2020-01-01' AND '2020-12-31';

SAVEPOINT s1;
DROP INDEX core.ix_ocorrencia_cobrade_data;
\echo '--- sem índice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT count(*) FROM core.ocorrencia WHERE cd_cobrade = '12100' AND dt_evento BETWEEN '2020-01-01' AND '2020-12-31';
ROLLBACK TO SAVEPOINT s1;

\echo
\echo '=== C2. Municípios vizinhos de todos os municípios (GiST em geom) ==='
\echo '--- com índice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT count(*) FROM core.municipio a JOIN core.municipio b
  ON a.cd_mun < b.cd_mun AND ST_Touches(a.geom, b.geom)
WHERE a.cd_uf = 52 AND b.cd_uf = 52;

SAVEPOINT s2;
DROP INDEX core.gx_municipio_geom;
\echo '--- sem índice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT count(*) FROM core.municipio a JOIN core.municipio b
  ON a.cd_mun < b.cd_mun AND ST_Touches(a.geom, b.geom)
WHERE a.cd_uf = 52 AND b.cd_uf = 52;
ROLLBACK TO SAVEPOINT s2;

\echo
\echo '=== C3. Municípios a até 50 km de um ponto (GiST em ponto_ref::geography) ==='
\echo '--- com índice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT count(*) FROM core.municipio
WHERE ST_DWithin(ponto_ref::geography, ST_SetSRID(ST_MakePoint(-51.25, -16.25), 4674)::geography, 50000);

SAVEPOINT s3;
DROP INDEX core.gx_municipio_ponto_geog;
\echo '--- sem índice'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT count(*) FROM core.municipio
WHERE ST_DWithin(ponto_ref::geography, ST_SetSRID(ST_MakePoint(-51.25, -16.25), 4674)::geography, 50000);
ROLLBACK TO SAVEPOINT s3;

\echo
\echo '=== C4. Recorrência hidrológica numa região (filtro por grupo COBRADE + caixa espacial) ==='
\echo '--- predicado com função na coluna: left(cd_cobrade, 2) = ''12'' (não usa índice)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT m.cd_mun, count(*) AS qtd
FROM core.municipio m
JOIN core.ocorrencia o ON o.cd_mun = m.cd_mun
WHERE left(o.cd_cobrade, 2) = '12'
  AND m.geom && ST_MakeEnvelope(-53, -18, -52, -17, 4674)
GROUP BY m.cd_mun ORDER BY qtd DESC LIMIT 10;

\echo '--- predicado reescrito como faixa: cd_cobrade BETWEEN ''12000'' AND ''12999'' (usa o B-tree)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT m.cd_mun, count(*) AS qtd
FROM core.municipio m
JOIN core.ocorrencia o ON o.cd_mun = m.cd_mun
WHERE o.cd_cobrade BETWEEN '12000' AND '12999'
  AND m.geom && ST_MakeEnvelope(-53, -18, -52, -17, 4674)
GROUP BY m.cd_mun ORDER BY qtd DESC LIMIT 10;

ROLLBACK;
\echo
\echo 'Benchmark concluído. Nenhuma alteração foi mantida (ROLLBACK).'
