# 09 - Consultas espaciais de referência

Consultas que motivaram as decisões do modelo físico. Todas são verificadas por `tests/sql/050_espacial.sql` sobre a amostra.

## Municípios vizinhos

```sql
SELECT v.cd_mun, v.nome
FROM core.municipio a
JOIN core.municipio v ON v.cd_mun <> a.cd_mun AND ST_Touches(a.geom, v.geom)
WHERE a.cd_mun = '4216602';          -- São José/SC
```

## Evento regional: mesmo grupo de desastre em municípios vizinhos, com até 7 dias de diferença

O S2iD registra uma ocorrência por município. Esta consulta reconstrói a visão regional de um mesmo evento climático, útil para planejamento de resposta e para detectar subnotificação em vizinhos.

```sql
SELECT a.chave_origem AS ocorrencia_a, ma.nome AS municipio_a,
       b.chave_origem AS ocorrencia_b, mb.nome AS municipio_b,
       abs(b.dt_evento - a.dt_evento) AS dias_entre
FROM core.ocorrencia a
JOIN core.municipio ma ON ma.cd_mun = a.cd_mun
JOIN core.ocorrencia b
  ON b.id_ocorrencia > a.id_ocorrencia
 AND b.cd_cobrade BETWEEN '12000' AND '12999'         -- grupo hidrológico (faixa, ver 07)
 AND a.cd_cobrade BETWEEN '12000' AND '12999'
 AND abs(b.dt_evento - a.dt_evento) <= 7
JOIN core.municipio mb ON mb.cd_mun = b.cd_mun AND ST_Touches(ma.geom, mb.geom);
```

## Municípios em um raio (metros, geodésico)

```sql
SELECT cd_mun, nome,
       round(ST_Distance(ponto_ref::geography, p.g) / 1000) AS km
FROM core.municipio,
     LATERAL (SELECT ST_SetSRID(ST_MakePoint(-48.55, -27.60), 4674)::geography AS g) p
WHERE ST_DWithin(ponto_ref::geography, p.g, 30000)
ORDER BY km;
```

`ST_DWithin` usa o índice `gx_municipio_ponto_geog`; `ST_Distance` sozinho no `WHERE` não usaria.

## Ocorrências em municípios com setor de risco mapeado para a mesma tipologia

```sql
SELECT o.chave_origem, o.dt_evento, ar.id_externo, ar.grau_risco
FROM risco.area_risco ar
JOIN core.ocorrencia o
  ON o.cd_mun = ar.cd_mun
 AND o.cd_cobrade = ar.cd_cobrade_relacionado
ORDER BY ar.grau_risco DESC, o.dt_evento DESC;
```

## Recorrência por município e grupo (visão materializada)

```sql
SELECT r.cd_mun, m.nome, r.grupo_cobrade, r.qtd_ocorrencias, r.anos_com_ocorrencia, r.total_pessoas_afetadas
FROM analitico.mv_recorrencia_municipio r
JOIN core.municipio m USING (cd_mun)
ORDER BY r.qtd_ocorrencias DESC
LIMIT 20;
```

## Mapa via contrato

```sql
SELECT api.fn_v1_ocorrencias_geojson(
    p_bbox       => ARRAY[-49.0, -28.0, -48.3, -27.4]::float8[],  -- Grande Florianópolis
    p_desde      => DATE '2023-01-01',
    p_cd_cobrade => '12');                                       -- todo o grupo hidrológico
```

O resultado é um GeoJSON pronto para QGIS, Leaflet, MapLibre ou para o app.
