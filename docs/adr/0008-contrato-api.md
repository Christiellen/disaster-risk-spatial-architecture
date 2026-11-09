# ADR-0008 - Contrato de integração versionado no schema api

**Situação:** Aceito

## Contexto
O mesmo dado atende painéis, um app mobile offline-first e outros sistemas. Se cada um ler as tabelas do core, qualquer refatoração quebra consumidores, e não há como saber quem depende de quê.

## Alternativas
1. Consumidores leem o core diretamente.
2. Camada de API em aplicação separada, com regras duplicadas.
3. Schema `api` com visões e funções versionadas (`v1_*`), JSON Schema publicado e papel de banco que só enxerga esse schema.

## Decisão
Opção 3. A v1 oferece visão tabular, GeoJSON filtrável e feed de sincronização por cursor. Pode ser publicada como HTTP por PostgREST ou pg_featureserv sem reescrever regras.

## Consequências
- O core pode evoluir: o contrato isola a mudança.
- O contrato é testado contra as respostas reais a cada CI (`tests/validar_contrato.py`).
- Regras de evolução explícitas: na v1 só se acrescenta; quebra exige v2 em paralelo.
- Funções `SECURITY DEFINER` com `search_path` fixo evitam conceder acesso ao core para o consumidor.
