# Dicionário de dados

> Gerado automaticamente por `python -m etl.gerar_dicionario` a partir do catálogo do banco.
> Não edite à mão: altere o `COMMENT ON` na migração e regenere.

## Sumário


**core**

- [`core.cobrade`](#corecobrade) - tabela: Árvore da Classificação e Codificação Brasileira de Desastres (COBRADE).
- [`core.indicador_dano`](#coreindicador_dano) - tabela: Catálogo dos indicadores de dano e prejuízo registrados por ocorrência (modelo longo, ver ADR-0005).
- [`core.municipio`](#coremunicipio) - tabela: Municípios brasileiros conforme código e malha do IBGE.
- [`core.ocorrencia`](#coreocorrencia) - tabela: Registro de desastre em um município. Unidade central do modelo.
- [`core.ocorrencia_dano`](#coreocorrencia_dano) - tabela: Valor de cada indicador de dano por ocorrência (modelo longo). Ausência de linha = não informado; zero = infor
- [`core.regiao`](#coreregiao) - tabela: Grandes regiões do IBGE.
- [`core.uf`](#coreuf) - tabela: Unidades da Federação.
- [`core.vw_cobrade_hierarquia`](#corevw_cobrade_hierarquia) - visão: COBRADE achatada: cada código com a descrição de todos os seus ancestrais.

**risco**

- [`risco.area_risco`](#riscoarea_risco) - tabela: Setores de risco mapeados (polígonos), associados ao município e opcionalmente a uma tipologia COBRADE.

**controle**

- [`controle.ajuste`](#controleajuste) - tabela: Correções automáticas aplicadas durante a carga. Nenhum valor é alterado sem deixar registro.
- [`controle.lote_carga`](#controlelote_carga) - tabela: Um registro por arquivo recebido. Base da rastreabilidade de qualquer linha do core até o arquivo de origem.
- [`controle.rejeicao`](#controlerejeicao) - tabela: Quarentena: linhas que violaram regras de qualidade, com o código da regra e o registro original completo.

**staging**

- [`staging.area_risco`](#stagingarea_risco) - tabela: Setores de risco recebidos em GeoJSON, antes da normalização.
- [`staging.atlas_ocorrencia`](#stagingatlas_ocorrencia) - tabela: Linhas do arquivo do Atlas Digital de Desastres, com colunas já mapeadas para nomes canônicos (etl/config/atla
- [`staging.ibge_malha`](#stagingibge_malha) - tabela: Geometrias da API de Malhas do IBGE, uma feição por linha, em GeoJSON.
- [`staging.ibge_municipio`](#stagingibge_municipio) - tabela: Cadastro de municípios da API de Localidades do IBGE (visão nivelada).

**hist**

- [`hist.ocorrencia`](#histocorrencia) - tabela: Changelog de core.ocorrencia. Mesmas colunas da tabela de origem, na mesma ordem, mais os metadados hist_*.
- [`hist.ocorrencia_dano`](#histocorrencia_dano) - tabela: Changelog de core.ocorrencia_dano.

**api**

- [`api.v1_ocorrencia`](#apiv1_ocorrencia) - visão: Contrato v1 da ocorrência. Identificador público = chave_origem; a chave substituta interna não é exposta.

**analitico**

- [`analitico.mv_recorrencia_municipio`](#analiticomv_recorrencia_municipio) - visão materializada: Recorrência de desastres por município e grupo COBRADE (quantidade, anos com ocorrência, pessoas afetadas, óbi

## core.cobrade

*Tabela.* Árvore da Classificação e Codificação Brasileira de Desastres (COBRADE).

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `cd_cobrade` | character(5) | sim | PK, UK |  | Código de 5 dígitos (categoria, grupo, subgrupo, tipo, subtipo). |
| `nivel` | text | sim |  |  | Nível do nó na hierarquia. |
| `cd_pai` | character(5) | não | FK → core.cobrade |  | Nó imediatamente superior. Nulo apenas para CATEGORIA. |
| `descricao` | text | sim |  |  | Descrição oficial da tipologia. |
| `classificavel` | boolean | sim | UK |  | Verdadeiro para nós-folha, os únicos aceitos na classificação de uma ocorrência. |
| `ativo` | boolean | sim |  | true | Permite descontinuar códigos sem apagar o histórico que os referencia. |

**Regras (CHECK)**

- `ck_cobrade_categoria_prefixo`: `CHECK (((cd_pai IS NULL) OR ("left"((cd_pai)::text, 1) = "left"((cd_cobrade)::text, 1))))`
- `ck_cobrade_raiz`: `CHECK (((nivel = 'CATEGORIA'::text) = (cd_pai IS NULL)))`
- `cobrade_cd_cobrade_check`: `CHECK ((cd_cobrade ~ '^[12][0-9]{4}$'::text))`
- `cobrade_nivel_check`: `CHECK ((nivel = ANY (ARRAY['CATEGORIA'::text, 'GRUPO'::text, 'SUBGRUPO'::text, 'TIPO'::text, 'SUBTIPO'::text])))`

**Índices**

- `ix_cobrade_pai` (btree): `btree (cd_pai)`
- `uq_cobrade_classificavel` (btree): `btree (cd_cobrade, classificavel)`

## core.indicador_dano

*Tabela.* Catálogo dos indicadores de dano e prejuízo registrados por ocorrência (modelo longo, ver ADR-0005).

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `cd_indicador` | text | sim | PK |  | Código do indicador. |
| `categoria` | text | sim |  |  | Categoria do dano. |
| `unidade` | text | sim |  |  | Unidade de medida do valor. |
| `descricao` | text | sim |  |  | Descrição do indicador. |
| `compoe_total_humano` | boolean | sim |  | false | Se o indicador entra no total de pessoas diretamente afetadas (calculado, nunca armazenado). |

**Regras (CHECK)**

- `ck_indicador_total_humano`: `CHECK (((NOT compoe_total_humano) OR (categoria = 'HUMANO'::text)))`
- `indicador_dano_categoria_check`: `CHECK ((categoria = ANY (ARRAY['HUMANO'::text, 'MATERIAL'::text, 'PREJUIZO_PUBLICO'::text, 'PREJUIZO_PRIVADO'::text])))`
- `indicador_dano_cd_indicador_check`: `CHECK ((cd_indicador ~ '^[A-Z][A-Z0-9_]+$'::text))`
- `indicador_dano_unidade_check`: `CHECK ((unidade = ANY (ARRAY['PESSOAS'::text, 'UNIDADES'::text, 'BRL'::text])))`

## core.municipio

*Tabela.* Municípios brasileiros conforme código e malha do IBGE.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `cd_mun` | character(7) | sim | PK |  | Código IBGE do município (7 dígitos; os 2 primeiros são a UF). |
| `cd_uf` | smallint | sim | FK → core.uf |  | UF do município. Deve coincidir com o prefixo do código (CHECK). |
| `nome` | text | sim |  |  | Nome oficial do município. |
| `geom` | geometry(MultiPolygon,4674) | não |  |  | Limite municipal (SIRGAS 2000). Opcional. |
| `area_km2` | numeric(12,3) | não |  | gerada | Área geodésica em km², calculada a partir da geometria (coluna gerada). |
| `ponto_ref` | geometry(Point,4674) | não |  | gerada | Ponto garantidamente interno ao polígono (ST_PointOnSurface), usado em consultas por raio e no app mobile. |

**Regras (CHECK)**

- `ck_mun_geom_valida`: `CHECK (((geom IS NULL) OR st_isvalid(geom)))`
- `ck_mun_prefixo_uf`: `CHECK (((substr((cd_mun)::text, 1, 2))::smallint = cd_uf))`
- `municipio_cd_mun_check`: `CHECK ((cd_mun ~ '^[0-9]{7}$'::text))`

**Índices**

- `gx_municipio_geom` (gist): `gist (geom)`
- `gx_municipio_ponto_geog` (gist): `gist (((ponto_ref)::geography))`
- `gx_municipio_ponto_ref` (gist): `gist (ponto_ref)`
- `ix_municipio_uf` (btree): `btree (cd_uf)`

## core.ocorrencia

*Tabela.* Registro de desastre em um município. Unidade central do modelo.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_ocorrencia` | bigint | sim | PK | identity | Chave substituta interna. Nunca exposta como identificador de negócio. |
| `chave_origem` | text | sim | UK |  | Chave natural estável: protocolo do S2iD quando existe; senão, hash determinístico de município + COBRADE + data do evento (ver ADR-0006). |
| `protocolo` | text | não |  |  | Protocolo do registro no S2iD, quando informado pela fonte. |
| `cd_mun` | character(7) | sim | FK → core.municipio |  | Município afetado. |
| `cd_cobrade` | character(5) | sim | FK → core.cobrade |  | Tipologia COBRADE. Só aceita nós-folha (FK composta com classificavel). |
| `cobrade_classificavel` | boolean | sim | FK → core.cobrade | true | Coluna técnica fixa em verdadeiro; viabiliza a FK composta que restringe a classificação a nós-folha. |
| `dt_evento` | date | sim |  |  | Data de início do evento adverso. |
| `dt_registro` | date | não |  |  | Data de registro no sistema. Não pode ser anterior ao evento. |
| `situacao` | text | não |  |  | Situação informada pela fonte. Domínio ainda aberto até o perfilamento completo (pendência P-02). |
| `id_lote_origem` | bigint | sim | FK → controle.lote_carga |  | Lote que criou ou atualizou por último o registro. |
| `linha_origem` | integer | sim |  |  | Linha do arquivo de origem no lote indicado. |
| `versao` | integer | sim |  | 1 | Versão do registro. Incrementada a cada alteração; usada em controle otimista de concorrência (ADR-0007). |
| `criado_em` | timestamp with time zone | sim |  | now() | Momento da criação. |
| `atualizado_em` | timestamp with time zone | sim |  | now() | Momento da última alteração. Base da sincronização incremental. |

**Regras (CHECK)**

- `ck_ocorrencia_atualizacao`: `CHECK ((atualizado_em >= criado_em))`
- `ck_ocorrencia_protocolo_formato`: `CHECK (((protocolo IS NULL) OR (protocolo ~ '^[A-Z0-9][A-Z0-9./-]{3,}$'::text)))`
- `ck_ocorrencia_registro_apos_evento`: `CHECK (((dt_registro IS NULL) OR (dt_registro >= dt_evento)))`
- `ocorrencia_cobrade_classificavel_check`: `CHECK (cobrade_classificavel)`
- `ocorrencia_dt_evento_check`: `CHECK ((dt_evento >= '1900-01-01'::date))`
- `ocorrencia_linha_origem_check`: `CHECK ((linha_origem > 0))`
- `ocorrencia_versao_check`: `CHECK ((versao >= 1))`

**Índices**

- `ix_ocorrencia_atualizado` (btree): `btree (atualizado_em)`
- `ix_ocorrencia_cobrade_data` (btree): `btree (cd_cobrade, dt_evento)`
- `ix_ocorrencia_lote` (btree): `btree (id_lote_origem)`
- `ix_ocorrencia_mun_data` (btree): `btree (cd_mun, dt_evento)`
- `ocorrencia_chave_origem_key` (btree): `btree (chave_origem)`
- `uq_ocorrencia_protocolo` (btree): `btree (protocolo) WHERE (protocolo IS NOT NULL)`

## core.ocorrencia_dano

*Tabela.* Valor de cada indicador de dano por ocorrência (modelo longo). Ausência de linha = não informado; zero = informado como zero.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_ocorrencia` | bigint | sim | FK → core.ocorrencia, PK |  | Ocorrência. |
| `cd_indicador` | text | sim | FK → core.indicador_dano, PK |  | Indicador de dano. |
| `valor` | numeric(18,2) | sim |  |  | Valor não negativo, na unidade definida em core.indicador_dano. |

**Regras (CHECK)**

- `ocorrencia_dano_valor_check`: `CHECK ((valor >= (0)::numeric))`

**Índices**

- `ix_dano_indicador` (btree): `btree (cd_indicador)`

## core.regiao

*Tabela.* Grandes regiões do IBGE.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `sigla_regiao` | character(2) | sim | PK |  | Sigla da região (N, NE, SE, S, CO). |
| `nome` | text | sim | UK |  | Nome da região. |

**Regras (CHECK)**

- `regiao_sigla_regiao_check`: `CHECK ((sigla_regiao = ANY (ARRAY['N'::bpchar, 'NE'::bpchar, 'SE'::bpchar, 'S'::bpchar, 'CO'::bpchar])))`

**Índices**

- `regiao_nome_key` (btree): `btree (nome)`

## core.uf

*Tabela.* Unidades da Federação.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `cd_uf` | smallint | sim | PK |  | Código IBGE da UF (2 dígitos). O primeiro dígito identifica a região. |
| `sigla_uf` | character(2) | sim | UK |  | Sigla da UF. |
| `nome` | text | sim | UK |  | Nome da UF. |
| `sigla_regiao` | character(2) | sim | FK → core.regiao |  | Região da UF. Coerência com o primeiro dígito do código é garantida por CHECK. |
| `geom` | geometry(MultiPolygon,4674) | não |  |  | Limite da UF (SIRGAS 2000). Opcional: o modelo funciona sem geometria. |

**Regras (CHECK)**

- `ck_uf_geom_valida`: `CHECK (((geom IS NULL) OR st_isvalid(geom)))`
- `ck_uf_regiao_coerente`: `CHECK (((((cd_uf / 10) = 1) AND (sigla_regiao = 'N'::bpchar)) OR (((cd_uf / 10) = 2) AND (sigla_regiao = 'NE'::bpchar)) OR (((cd_uf / 10) = 3) AND (sigla_regiao = 'SE'::bpchar)) OR (((cd_uf / 10) = 4) AND (sigla_regiao = 'S'::bpchar)) OR (((cd_uf / 10) = 5) AND (sigla_regiao = 'CO'::bpchar))))`
- `uf_cd_uf_check`: `CHECK (((cd_uf >= 11) AND (cd_uf <= 53)))`
- `uf_sigla_uf_check`: `CHECK ((sigla_uf ~ '^[A-Z]{2}$'::text))`

**Índices**

- `gx_uf_geom` (gist): `gist (geom)`
- `ix_uf_regiao` (btree): `btree (sigla_regiao)`
- `uf_nome_key` (btree): `btree (nome)`
- `uf_sigla_uf_key` (btree): `btree (sigla_uf)`

## core.vw_cobrade_hierarquia

*Visão.* COBRADE achatada: cada código com a descrição de todos os seus ancestrais.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `cd_cobrade` | character(5) | não |  |  |  |
| `descricao` | text | não |  |  |  |
| `nivel` | text | não |  |  |  |
| `classificavel` | boolean | não |  |  |  |
| `categoria` | text | não |  |  |  |
| `grupo` | text | não |  |  |  |
| `subgrupo` | text | não |  |  |  |
| `tipo` | text | não |  |  |  |
| `subtipo` | text | não |  |  |  |

## risco.area_risco

*Tabela.* Setores de risco mapeados (polígonos), associados ao município e opcionalmente a uma tipologia COBRADE.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_area` | bigint | sim | PK | identity | Chave substituta. |
| `fonte` | text | sim | UK |  | Instituição/produto de origem (ex.: SGB_SETORIZACAO). |
| `id_externo` | text | sim | UK |  | Identificador do setor na fonte. Com a fonte, forma a chave natural. |
| `cd_mun` | character(7) | não | FK → core.municipio |  | Município do setor. Preenchido pela fonte ou, se ausente, por interseção espacial. |
| `tipologia` | text | sim |  |  | Tipologia de processo descrita pela fonte (ex.: deslizamento, inundação). |
| `grau_risco` | text | sim |  |  | Grau de risco normalizado. |
| `cd_cobrade_relacionado` | character(5) | não | FK → core.cobrade |  | Código COBRADE equivalente, quando a correspondência é inequívoca. |
| `dt_referencia` | date | não |  |  | Data de referência do mapeamento. |
| `geom` | geometry(MultiPolygon,4674) | sim |  |  | Polígono do setor (SIRGAS 2000). Válido e não vazio. |
| `id_lote_origem` | bigint | sim | FK → controle.lote_carga |  | Lote de carga de origem. |

**Regras (CHECK)**

- `area_risco_grau_risco_check`: `CHECK ((grau_risco = ANY (ARRAY['BAIXO'::text, 'MEDIO'::text, 'ALTO'::text, 'MUITO_ALTO'::text])))`
- `ck_area_risco_geom_nao_vazia`: `CHECK ((NOT st_isempty(geom)))`
- `ck_area_risco_geom_valida`: `CHECK (st_isvalid(geom))`

**Índices**

- `gx_area_risco_geom` (gist): `gist (geom)`
- `ix_area_risco_cobrade` (btree): `btree (cd_cobrade_relacionado)`
- `ix_area_risco_lote` (btree): `btree (id_lote_origem)`
- `ix_area_risco_mun` (btree): `btree (cd_mun)`
- `uq_area_risco_origem` (btree): `btree (fonte, id_externo)`

## controle.ajuste

*Tabela.* Correções automáticas aplicadas durante a carga. Nenhum valor é alterado sem deixar registro.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_ajuste` | bigint | sim | PK | identity | Identificador do ajuste. |
| `id_lote` | bigint | sim | FK → controle.lote_carga |  | Lote em que o ajuste foi aplicado. |
| `linha_origem` | integer | sim |  |  | Linha do arquivo de origem. |
| `campo` | text | sim |  |  | Campo ajustado. |
| `valor_original` | text | não |  |  | Valor recebido. |
| `valor_ajustado` | text | sim |  |  | Valor gravado no core. |
| `regra` | text | sim |  |  | Regra que justificou o ajuste. |

**Índices**

- `ix_ajuste_lote` (btree): `btree (id_lote)`

## controle.lote_carga

*Tabela.* Um registro por arquivo recebido. Base da rastreabilidade de qualquer linha do core até o arquivo de origem.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_lote` | bigint | sim | PK | identity | Identificador do lote. |
| `fonte` | text | sim | UK |  | Fonte de dados do arquivo (domínio fechado). |
| `arquivo` | text | sim |  |  | Nome do arquivo recebido. |
| `hash_sha256` | character(64) | sim | UK |  | Hash SHA-256 do conteúdo do arquivo. Impede recarga do mesmo arquivo (idempotência). |
| `status` | text | sim |  | 'RECEBIDO'::text | Ciclo de vida do lote: RECEBIDO -> EM_STAGING -> PROCESSADO \| FALHOU. |
| `linhas_lidas` | integer | não |  |  | Quantidade de linhas lidas do arquivo. |
| `linhas_aceitas` | integer | não |  |  | Linhas que passaram nas regras e foram gravadas no core. |
| `linhas_rejeitadas` | integer | não |  |  | Linhas enviadas para controle.rejeicao. |
| `colunas_nao_mapeadas` | text[] | sim |  | '{}'::text[] | Colunas do arquivo sem mapeamento canônico. Preservadas em staging.*.extras para não perder informação. |
| `iniciado_em` | timestamp with time zone | sim |  | now() | Início do processamento. |
| `concluido_em` | timestamp with time zone | não |  |  | Fim do processamento. |
| `observacao` | text | não |  |  | Texto livre (ex.: mensagem de erro em caso de falha). |

**Regras (CHECK)**

- `ck_lote_conclusao`: `CHECK (((concluido_em IS NULL) OR (concluido_em >= iniciado_em)))`
- `ck_lote_contagem`: `CHECK (((status <> 'PROCESSADO'::text) OR ((linhas_aceitas IS NOT NULL) AND (linhas_rejeitadas IS NOT NULL) AND ((linhas_aceitas + linhas_rejeitadas) <= linhas_lidas))))`
- `lote_carga_fonte_check`: `CHECK ((fonte = ANY (ARRAY['ATLAS_DESASTRES'::text, 'IBGE_MUNICIPIOS'::text, 'IBGE_MALHA_MUN'::text, 'IBGE_MALHA_UF'::text, 'SGB_AREAS_RISCO'::text, 'AMOSTRA'::text])))`
- `lote_carga_hash_sha256_check`: `CHECK ((hash_sha256 ~ '^[0-9a-f]{64}$'::text))`
- `lote_carga_linhas_aceitas_check`: `CHECK ((linhas_aceitas >= 0))`
- `lote_carga_linhas_lidas_check`: `CHECK ((linhas_lidas >= 0))`
- `lote_carga_linhas_rejeitadas_check`: `CHECK ((linhas_rejeitadas >= 0))`
- `lote_carga_status_check`: `CHECK ((status = ANY (ARRAY['RECEBIDO'::text, 'EM_STAGING'::text, 'PROCESSADO'::text, 'FALHOU'::text])))`

**Índices**

- `uq_lote_fonte_hash` (btree): `btree (fonte, hash_sha256)`

## controle.rejeicao

*Tabela.* Quarentena: linhas que violaram regras de qualidade, com o código da regra e o registro original completo.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_rejeicao` | bigint | sim | PK | identity | Identificador da rejeição. |
| `id_lote` | bigint | sim | FK → controle.lote_carga |  | Lote de origem. |
| `linha_origem` | integer | sim |  |  | Número da linha no arquivo de origem (1 = primeira linha de dados). |
| `regra` | text | sim |  |  | Código da regra de qualidade violada (catálogo em docs/06-regras-de-integridade.md). |
| `detalhe` | text | não |  |  | Descrição legível da violação. |
| `registro` | jsonb | sim |  |  | Registro original, como recebido, em JSON. |
| `rejeitado_em` | timestamp with time zone | sim |  | now() | Momento da rejeição. |

**Regras (CHECK)**

- `rejeicao_linha_origem_check`: `CHECK ((linha_origem > 0))`

**Índices**

- `ix_rejeicao_lote_regra` (btree): `btree (id_lote, regra)`

## staging.area_risco

*Tabela.* Setores de risco recebidos em GeoJSON, antes da normalização.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_lote` | bigint | sim | FK → controle.lote_carga, PK |  |  |
| `linha_origem` | integer | sim | PK |  |  |
| `fonte` | text | não |  |  |  |
| `id_externo` | text | não |  |  |  |
| `cd_mun` | text | não |  |  |  |
| `tipologia` | text | não |  |  |  |
| `grau_risco` | text | não |  |  |  |
| `cobrade` | text | não |  |  |  |
| `dt_referencia` | text | não |  |  |  |
| `geojson` | text | não |  |  |  |

## staging.atlas_ocorrencia

*Tabela.* Linhas do arquivo do Atlas Digital de Desastres, com colunas já mapeadas para nomes canônicos (etl/config/atlas_colunas.yaml), ainda sem tipagem.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_lote` | bigint | sim | FK → controle.lote_carga, PK |  | Lote de carga. |
| `linha_origem` | integer | sim | PK |  | Linha no arquivo (1 = primeira linha de dados). |
| `protocolo` | text | não |  |  | Protocolo S2iD, como recebido. |
| `uf` | text | não |  |  | UF, como recebida. |
| `cd_mun` | text | não |  |  | Código IBGE do município, como recebido. |
| `nome_mun` | text | não |  |  | Nome do município, como recebido (apenas conferência). |
| `dt_evento` | text | não |  |  | Data do evento, como recebida. |
| `dt_registro` | text | não |  |  | Data de registro, como recebida. |
| `cobrade` | text | não |  |  | Código COBRADE, como recebido. |
| `cobrade_desc` | text | não |  |  | Descrição da tipologia, como recebida (apenas conferência). |
| `situacao` | text | não |  |  | Situação do registro, como recebida. |
| `danos` | jsonb | sim |  | '{}'::jsonb | Valores de dano como recebidos, indexados pelo código do indicador. |
| `extras` | jsonb | sim |  | '{}'::jsonb | Colunas do arquivo sem mapeamento canônico, preservadas integralmente. |

## staging.ibge_malha

*Tabela.* Geometrias da API de Malhas do IBGE, uma feição por linha, em GeoJSON.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_lote` | bigint | sim | FK → controle.lote_carga, PK |  |  |
| `linha_origem` | integer | sim | PK |  |  |
| `nivel` | text | sim |  |  |  |
| `codarea` | text | não |  |  |  |
| `geojson` | text | não |  |  |  |

**Regras (CHECK)**

- `ibge_malha_nivel_check`: `CHECK ((nivel = ANY (ARRAY['MUN'::text, 'UF'::text])))`

## staging.ibge_municipio

*Tabela.* Cadastro de municípios da API de Localidades do IBGE (visão nivelada).

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_lote` | bigint | sim | FK → controle.lote_carga, PK |  |  |
| `linha_origem` | integer | sim | PK |  |  |
| `cd_mun` | text | não |  |  |  |
| `nome_mun` | text | não |  |  |  |
| `cd_uf` | text | não |  |  |  |
| `sigla_uf` | text | não |  |  |  |
| `nome_uf` | text | não |  |  |  |
| `sigla_regiao` | text | não |  |  |  |

## hist.ocorrencia

*Tabela.* Changelog de core.ocorrencia. Mesmas colunas da tabela de origem, na mesma ordem, mais os metadados hist_*.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_ocorrencia` | bigint | sim |  |  |  |
| `chave_origem` | text | sim |  |  |  |
| `protocolo` | text | não |  |  |  |
| `cd_mun` | character(7) | sim |  |  |  |
| `cd_cobrade` | character(5) | sim |  |  |  |
| `cobrade_classificavel` | boolean | sim |  |  |  |
| `dt_evento` | date | sim |  |  |  |
| `dt_registro` | date | não |  |  |  |
| `situacao` | text | não |  |  |  |
| `id_lote_origem` | bigint | sim |  |  |  |
| `linha_origem` | integer | sim |  |  |  |
| `versao` | integer | sim |  |  |  |
| `criado_em` | timestamp with time zone | sim |  |  |  |
| `atualizado_em` | timestamp with time zone | sim |  |  |  |
| `hist_operacao` | character(1) | sim |  |  | I = inclusão, U = alteração, D = exclusão (imagem anterior à exclusão). |
| `hist_registrado_em` | timestamp with time zone | sim |  |  | Momento da operação (horário da transação). |
| `hist_usuario` | text | sim |  |  | Papel de banco que executou a operação. |
| `hist_id` | bigint | sim | PK | identity | Identificador sequencial do evento de histórico. |

**Regras (CHECK)**

- `ocorrencia_hist_operacao_check`: `CHECK ((hist_operacao = ANY (ARRAY['I'::bpchar, 'U'::bpchar, 'D'::bpchar])))`

**Índices**

- `ix_hist_ocorrencia_chave` (btree): `btree (chave_origem, hist_registrado_em)`
- `ix_hist_ocorrencia_tempo` (btree): `btree (hist_registrado_em)`

## hist.ocorrencia_dano

*Tabela.* Changelog de core.ocorrencia_dano.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id_ocorrencia` | bigint | sim |  |  |  |
| `cd_indicador` | text | sim |  |  |  |
| `valor` | numeric(18,2) | sim |  |  |  |
| `hist_operacao` | character(1) | sim |  |  | I = inclusão, U = alteração, D = exclusão. |
| `hist_registrado_em` | timestamp with time zone | sim |  |  | Momento da operação. |
| `hist_usuario` | text | sim |  |  | Papel de banco que executou a operação. |
| `hist_id` | bigint | sim | PK | identity | Identificador sequencial do evento de histórico. |

**Regras (CHECK)**

- `ocorrencia_dano_hist_operacao_check`: `CHECK ((hist_operacao = ANY (ARRAY['I'::bpchar, 'U'::bpchar, 'D'::bpchar])))`

**Índices**

- `ix_hist_dano_ocorrencia` (btree): `btree (id_ocorrencia, hist_registrado_em)`

## api.v1_ocorrencia

*Visão.* Contrato v1 da ocorrência. Identificador público = chave_origem; a chave substituta interna não é exposta.

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `id` | text | não |  |  |  |
| `protocolo` | text | não |  |  |  |
| `cd_mun` | character(7) | não |  |  |  |
| `municipio` | text | não |  |  |  |
| `uf` | character(2) | não |  |  |  |
| `cd_cobrade` | character(5) | não |  |  |  |
| `tipologia` | text | não |  |  |  |
| `grupo_cobrade` | text | não |  |  |  |
| `dt_evento` | date | não |  |  |  |
| `dt_registro` | date | não |  |  |  |
| `situacao` | text | não |  |  |  |
| `danos` | jsonb | não |  |  |  |
| `total_pessoas_afetadas` | bigint | não |  |  |  |
| `longitude` | numeric | não |  |  |  |
| `latitude` | numeric | não |  |  |  |
| `versao` | integer | não |  |  |  |
| `atualizado_em` | timestamp with time zone | não |  |  |  |

## analitico.mv_recorrencia_municipio

*Visão materializada.* Recorrência de desastres por município e grupo COBRADE (quantidade, anos com ocorrência, pessoas afetadas, óbitos).

| Coluna | Tipo | Obrigatória | Chave | Padrão | Descrição |
|---|---|---|---|---|---|
| `cd_mun` | character(7) | não |  |  |  |
| `cd_uf` | smallint | não |  |  |  |
| `grupo_cobrade` | text | não |  |  |  |
| `qtd_ocorrencias` | bigint | não |  |  |  |
| `anos_com_ocorrencia` | bigint | não |  |  |  |
| `primeira_ocorrencia` | date | não |  |  |  |
| `ultima_ocorrencia` | date | não |  |  |  |
| `total_pessoas_afetadas` | bigint | não |  |  |  |
| `total_obitos` | bigint | não |  |  |  |

**Índices**

- `uq_mv_recorrencia` (btree): `btree (cd_mun, grupo_cobrade)`
