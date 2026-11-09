# 04 - Modelos lógico e físico

## Modelo lógico (núcleo)

```mermaid
erDiagram
    regiao {
        char2 sigla_regiao PK
        text nome UK
    }
    uf {
        smallint cd_uf PK
        char2 sigla_uf UK
        text nome UK
        char2 sigla_regiao FK
        multipolygon geom
    }
    municipio {
        char7 cd_mun PK
        smallint cd_uf FK
        text nome
        multipolygon geom
        numeric area_km2 "gerada"
        point ponto_ref "gerada"
    }
    cobrade {
        char5 cd_cobrade PK
        text nivel
        char5 cd_pai FK
        text descricao
        boolean classificavel
        boolean ativo
    }
    ocorrencia {
        bigint id_ocorrencia PK
        text chave_origem UK
        text protocolo UK "parcial"
        char7 cd_mun FK
        char5 cd_cobrade FK
        boolean cobrade_classificavel FK
        date dt_evento
        date dt_registro
        text situacao
        bigint id_lote_origem FK
        integer linha_origem
        integer versao
        timestamptz criado_em
        timestamptz atualizado_em
    }
    indicador_dano {
        text cd_indicador PK
        text categoria
        text unidade
        boolean compoe_total_humano
    }
    ocorrencia_dano {
        bigint id_ocorrencia PK, FK
        text cd_indicador PK, FK
        numeric valor
    }
    area_risco {
        bigint id_area PK
        text fonte UK
        text id_externo UK
        char7 cd_mun FK
        text grau_risco
        char5 cd_cobrade_relacionado FK
        multipolygon geom
    }
    lote_carga {
        bigint id_lote PK
        text fonte UK
        char64 hash_sha256 UK
        text status
    }
    regiao ||--o{ uf : ""
    uf ||--o{ municipio : ""
    municipio ||--o{ ocorrencia : ""
    cobrade ||--o{ cobrade : ""
    cobrade ||--o{ ocorrencia : "folha"
    ocorrencia ||--o{ ocorrencia_dano : ""
    indicador_dano ||--o{ ocorrencia_dano : ""
    municipio ||--o{ area_risco : ""
    lote_carga ||--o{ ocorrencia : ""
    lote_carga ||--o{ area_risco : ""
```

Estruturas de apoio (staging, histórico, rejeições, ajustes) estão no [dicionário de dados](05-dicionario-de-dados.md).

## Decisões do modelo físico

| Tema | Decisão | Motivo |
|---|---|---|
| Tipos de código | `char(7)` / `char(5)` com CHECK de regex, não inteiro | Códigos são identificadores, não quantidades; preserva zeros à esquerda e impede aritmética sem sentido |
| Chave da ocorrência | `bigint identity` interno + `chave_origem` única | Chave substituta estável para FKs; chave natural para idempotência e para o contrato público (ADR-0006) |
| COBRADE folha | FK composta `(cd_cobrade, cobrade_classificavel)` -> `cobrade (cd_cobrade, classificavel)` com a coluna fixa em `true` | Garante no banco, sem gatilho, que só folhas classificam (ADR-0004) |
| Coerência município x UF | CHECK `substr(cd_mun,1,2) = cd_uf` | O código IBGE carrega a UF; a redundância é verificada, não confiada |
| Colunas derivadas | `area_km2` e `ponto_ref` como `GENERATED ALWAYS ... STORED` | Calculadas uma vez, nunca divergem da geometria |
| `ponto_ref` | `ST_PointOnSurface`, não `ST_Centroid` | Centroide pode cair fora de municípios côncavos ou com ilhas; o ponto na superfície é sempre interno |
| Distâncias | Índice GiST de expressão em `ponto_ref::geography` | Raio em metros com precisão geodésica e uso de índice ([07](07-desempenho.md)) |
| Danos | Tabela longa `ocorrencia_dano` + catálogo `indicador_dano` | Novos indicadores sem alterar estrutura; unidade e categoria explícitas (ADR-0005) |
| Valores | `numeric(18,2)` com CHECK `>= 0` + gatilho de inteiro para PESSOAS/UNIDADES | Monetário exato; contagem de pessoas não pode ser fracionada |
| Datas | `date` para evento e registro; `timestamptz` para metadados | Eventos são datas civis; metadados precisam de instante absoluto |
| Particionamento | Não adotado | Volume esperado (centenas de milhares de linhas) não justifica; reavaliar acima de dezenas de milhões (risco RT-07) |

## Índices

| Índice | Tipo | Consulta atendida |
|---|---|---|
| `ix_ocorrencia_cobrade_data (cd_cobrade, dt_evento)` | B-tree | Filtro por tipologia/grupo e período |
| `ix_ocorrencia_mun_data (cd_mun, dt_evento)` | B-tree | Histórico de um município; FK |
| `ix_ocorrencia_atualizado (atualizado_em)` | B-tree | Alterações recentes |
| `uq_ocorrencia_protocolo` | B-tree único parcial (`WHERE protocolo IS NOT NULL`) | Unicidade do protocolo sem penalizar nulos |
| `gx_municipio_geom` | GiST | Vizinhança, interseção, caixa espacial |
| `gx_municipio_ponto_geog ((ponto_ref::geography))` | GiST de expressão | Busca por raio em metros |
| `gx_area_risco_geom` | GiST | Interseção setor x município/ocorrência |
| Índices de FK | B-tree | Todo FK tem índice (verificado pelo teste 010) |

Os ganhos medidos estão em [07 - Desempenho](07-desempenho.md).
