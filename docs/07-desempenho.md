# 07 - Desempenho e consistência

## Método

`scripts/benchmark.sql` gera volume sintético de ordem de grandeza nacional (5.625 polígonos em grade, simulando os ~5.570 municípios, e 200 mil ocorrências), executa cada consulta **com e sem** o índice correspondente e desfaz tudo ao final (`ROLLBACK`). O PostgreSQL permite `DROP INDEX` dentro de transação, o que torna a comparação segura em qualquer banco.

Para resultados comparáveis entre máquinas: paralelismo e JIT desligados, `ANALYZE` antes das medições.

```bash
make benchmark      # ou: PGDATABASE=s2id_teste psql -X -f scripts/benchmark.sql
```

## Resultados

Medidos em PostgreSQL 16 + PostGIS 3.4, em ambiente de desenvolvimento. Saída completa dos planos: [`evidencias/benchmark_saida.txt`](evidencias/benchmark_saida.txt). Os valores absolutos variam com o hardware; a **razão** entre os cenários é o que importa.

| Consulta | Sem índice | Com índice | Ganho | Índice |
|---|---:|---:|---:|---|
| C1. Inundações em um ano | 10,9 ms (Seq Scan) | 0,7 ms (Bitmap Index Scan) | ~15x | `ix_ocorrencia_cobrade_data` |
| C2. Pares de municípios vizinhos (todos x todos) | 3.452 ms | 175 ms | ~20x | `gx_municipio_geom` (GiST) |
| C3. Municípios a até 50 km de um ponto | 6,2 ms (Seq Scan) | 0,19 ms | ~32x | `gx_municipio_ponto_geog` (GiST de expressão) |

## Achado: predicado não sargável

Na consulta C4 (ocorrências hidrológicas numa região), o filtro por grupo COBRADE escrito como `left(cd_cobrade, 2) = '12'` **não usa índice**: aplicar função à coluna impede o B-tree e o plano cai em Seq Scan das 200 mil linhas.

| C4. Variante | Tempo | Plano da tabela de ocorrências |
|---|---:|---|
| `left(cd_cobrade, 2) = '12'` | 35,8 ms | Seq Scan |
| `cd_cobrade BETWEEN '12000' AND '12999'` | 16,2 ms | Bitmap Index Scan em `ix_ocorrencia_cobrade_data` |

Como o código COBRADE é hierárquico por prefixo, todo filtro por grupo pode virar faixa. **A recomendação foi aplicada no contrato** (`api.fn_v1_ocorrencias_geojson` converte o prefixo informado em faixa com `rpad`), e o resultado continua coberto pelo teste 060.

## Recomendações

| # | Recomendação | Situação |
|---|---|---|
| D1 | Filtrar grupos COBRADE por faixa, nunca por função na coluna | Aplicada na API |
| D2 | Distâncias sempre em `geography` sobre `ponto_ref`, com índice de expressão; evitar `ST_Distance` sem `ST_DWithin` | Aplicada |
| D3 | Pré-filtro `&&` (caixa) antes de predicados exatos (`ST_Intersects`, `ST_Touches`); o PostGIS faz isso automaticamente quando há GiST | Aplicada |
| D4 | Agregações históricas em visão materializada (`analitico.mv_recorrencia_municipio`), atualizada após cada carga com `REFRESH CONCURRENTLY` | Aplicada |
| D5 | Para o app mobile, enviar `ponto_ref` e não o polígono completo; polígonos simplificados por nível de zoom, se necessários, em tabela própria | Recomendada |
| D6 | Malha municipal na qualidade "intermediária" para análise; "máxima" apenas quando a precisão de borda for requisito | Recomendada |
| D7 | Reavaliar particionamento por ano de `dt_evento` se a tabela passar de dezenas de milhões de linhas | Monitorar (RT-07) |
| D8 | Monitorar índices não usados com `pg_stat_user_indexes` após 30 dias de uso real | Recomendada |

## Consistência

- Toda promoção de lote ocorre em **uma transação**: ou o lote entra inteiro (com suas rejeições), ou nada entra.
- Leitores nunca veem estado parcial: MVCC do PostgreSQL + `REFRESH MATERIALIZED VIEW CONCURRENTLY`.
- O cursor de sincronização usa `hist_id`; o risco de lacuna com transações concorrentes está descrito em RT-05.
