# 08 - Mapa de dados e integrações

## Fluxo de dados

```mermaid
flowchart TB
    subgraph Entrada
        F1[Atlas CSV/XLSX] -->|etl.carregar_atlas| S1[staging.atlas_ocorrencia]
        F2[IBGE Localidades JSON] -->|etl.carregar_ibge| S2[staging.ibge_municipio]
        F3[IBGE Malhas GeoJSON] -->|etl.carregar_ibge| S3[staging.ibge_malha]
        F4[SGB setores GeoJSON] -->|etl.carregar_areas_risco| S4[staging.area_risco]
    end
    S2 -->|fn_processar_lote_ibge_municipios| C1[core.uf / core.municipio]
    S3 -->|fn_processar_lote_ibge_malha| C1
    S1 -->|fn_processar_lote_atlas| C2[core.ocorrencia / core.ocorrencia_dano]
    S4 -->|fn_processar_lote_areas_risco| R1[risco.area_risco]
    S1 & S2 & S3 & S4 -.->|violações| Q[controle.rejeicao / controle.ajuste]
    C2 -->|gatilhos| H[hist.*]
    C1 & C2 --> A1[api.v1_ocorrencia]
    A1 --> A2[api.fn_v1_ocorrencias_geojson]
    H --> A3[api.fn_v1_sincronizar]
    A1 --> A3
    C2 --> M[analitico.mv_recorrencia_municipio]
```

**Ordem obrigatória de carga:** território (cadastro, depois malhas) -> ocorrências -> áreas de risco. Ocorrências e setores dependem do município existir.

## Mapa de dados por campo (Atlas -> core -> contrato)

| Arquivo (normalizado) | Staging | Core | API v1 | Transformação |
|---|---|---|---|---|
| `protocolo` | `protocolo` | `protocolo`, `chave_origem` | `protocolo`, `id` | Maiúsculas; ausente -> chave por hash |
| `uf` | `uf` | (validação apenas) | `uf` (do cadastro) | Conferida contra o município (R03) |
| `cod_ibge_mun` | `cd_mun` | `cd_mun` | `cd_mun` | Só dígitos; 6 dígitos completado (A01) |
| `nome_municipio` | `nome_mun` | (não gravado) | `municipio` (do cadastro) | Cadastro IBGE é a fonte do nome |
| `data_evento` | `dt_evento` | `dt_evento` | `dt_evento` | ISO, dd/mm/aaaa ou série Excel |
| `data_registro` | `dt_registro` | `dt_registro` | `dt_registro` | Idem |
| `cod_cobrade` | `cobrade` | `cd_cobrade` | `cd_cobrade`, `tipologia`, `grupo_cobrade` | Extrai 5 dígitos; descrição vem da árvore |
| `status` | `situacao` | `situacao` | `situacao` | Texto aparado (domínio pendente, P-02) |
| `dh_*`, `dm_*`, `pepl_*`, `pepr_*` | `danos` (jsonb) | `ocorrencia_dano` | `danos`, `total_pessoas_afetadas` | Número pt-BR/en-US; total calculado |
| demais colunas | `extras` (jsonb) | - | - | Preservadas para análise futura |
| - | - | `ponto_ref` (município) | `longitude`, `latitude`, geometria GeoJSON | `ST_PointOnSurface` da malha |

## Contrato de integração v1

Único ponto de acesso para consumidores externos. Papel de banco `s2id_consumidor` só enxerga o schema `api` (verificado no teste 060).

| Interface | Uso | Esquema |
|---|---|---|
| `api.v1_ocorrencia` (visão) | Consulta tabular, painéis, outros sistemas | [`contracts/ocorrencia.v1.schema.json`](../contracts/ocorrencia.v1.schema.json) |
| `api.fn_v1_ocorrencias_geojson(bbox, desde, cobrade, limite)` | Mapas: FeatureCollection filtrada por caixa, data e prefixo COBRADE | Feições cujas `properties` seguem o esquema da ocorrência |
| `api.fn_v1_sincronizar(cursor, limite)` | Clientes offline-first: alterações desde o último cursor | [`contracts/sincronizacao.v1.schema.json`](../contracts/sincronizacao.v1.schema.json) |

Exemplo de página de sincronização: [`evidencias/exemplo_sincronizacao.txt`](evidencias/exemplo_sincronizacao.txt).

### Regras de evolução do contrato

- Na v1 só se **acrescentam** campos opcionais. Consumidores devem ignorar campos desconhecidos (`additionalProperties: true`).
- Remover, renomear ou mudar tipo de campo cria `api.v2_*` ao lado da v1, com prazo de convivência combinado.
- O identificador público é `chave_origem`; a chave substituta interna nunca é exposta, para que reprocessamentos não mudem identificadores.
- `tests/validar_contrato.py` valida as respostas reais do banco contra os esquemas a cada execução da CI: uma migração que quebre o contrato falha antes de chegar ao consumidor.

### Protocolo de sincronização para o app offline-first

```mermaid
sequenceDiagram
    participant App as App (offline-first)
    participant API as api.fn_v1_sincronizar
    App->>API: cursor = 0 (primeira vez)
    API-->>App: alteracoes[], cursor = 1.240, tem_mais = true
    App->>App: aplica GRAVAR/EXCLUIR localmente, guarda cursor
    App->>API: cursor = 1.240
    API-->>App: alteracoes[], cursor = 1.302, tem_mais = false
    Note over App: Sem conexão: trabalha com a base local
    App->>API: ao reconectar, cursor = 1.302
    Note over App,API: Alteração enviada pelo app leva a "versao" lida.<br/>Se o servidor tiver versão maior, a gravação é recusada<br/>(serialization_failure) e o app resolve o conflito.
```
