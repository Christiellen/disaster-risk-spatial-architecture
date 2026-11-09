# Disaster-Risk-Spatial-Architecture

Arquitetura de dados geoespacial em **PostgreSQL + PostGIS** para registros de desastres no Brasil, construída sobre dados públicos da Defesa Civil Nacional (Atlas Digital de Desastres) e do IBGE.

O projeto reproduz o trabalho de uma **Fase 0 de evolução de sistema legado**: inventariar as fontes, reconciliar o dado real com o que se espera dele, consolidar o baseline as-is/to-be, modelar em três níveis, garantir integridade, histórico e rastreabilidade no próprio banco, e publicar um contrato de integração estável para painéis e para um app mobile offline-first.

> Projeto pessoal de portfólio. Não tem vínculo com a Sedec/MIDR nem representa a estrutura interna de qualquer sistema oficial. Os dados de `data/sample/` são **sintéticos** (ver abaixo).

<details>
<summary><b>English summary</b></summary>

Geospatial data architecture on PostgreSQL/PostGIS for Brazilian disaster records, built on public data from the National Civil Defense (Digital Atlas of Disasters) and IBGE. It mirrors a "Phase 0" legacy-modernization effort: source inventory, as-is/to-be baseline, conceptual/logical/physical models, in-database integrity (composite FKs, checks, triggers), trigger-based changelog with optimistic concurrency, traceable batch loads with a quarantine table, an index benchmark with measured gains, a versioned integration contract (tabular view, GeoJSON, incremental sync for offline-first clients) validated against JSON Schema, and architecture decision records. Everything is tested in CI.
</details>

## O que está aqui

| Artefato | Onde |
|---|---|
| Inventário técnico de bases e insumos | [docs/01](docs/01-inventario-tecnico.md) |
| Baseline de arquitetura as-is / to-be | [docs/02](docs/02-baseline-as-is-to-be.md) |
| Modelo conceitual | [docs/03](docs/03-modelo-conceitual.md) |
| Modelos lógico e físico, índices | [docs/04](docs/04-modelos-logico-e-fisico.md) |
| Dicionário de dados (gerado do banco) | [docs/05](docs/05-dicionario-de-dados.md) |
| Regras de integridade, histórico, versionamento e rastreabilidade | [docs/06](docs/06-regras-de-integridade.md) |
| Desempenho: benchmark e recomendações | [docs/07](docs/07-desempenho.md) |
| Mapa de dados e integrações, contrato v1 | [docs/08](docs/08-mapa-de-dados-e-integracoes.md) |
| Consultas espaciais de referência | [docs/09](docs/09-consultas-espaciais.md) |
| Riscos técnicos, pendências e evolução | [docs/10](docs/10-riscos-e-pendencias.md) |
| Critérios de aceite, testes e homologação | [docs/11](docs/11-criterios-de-aceite.md) |
| Registro de decisões arquiteturais | [docs/adr](docs/adr/README.md) |

## Destaques técnicos

- **Integridade no banco, não só na carga.** Só códigos COBRADE folha classificam ocorrências, por FK composta (sem gatilho). Prefixo do município coerente com a UF por CHECK. Pessoas não podem ser fracionadas.
- **Carga rastreável e idempotente.** Cada arquivo é um lote identificado por SHA-256; recarregar não duplica. Linhas inválidas vão para quarentena com a regra violada e o registro original; correções automáticas ficam registradas com valor antes e depois.
- **Histórico e versão.** Changelog por gatilho, consulta "como era em uma data", versão por registro e recusa de gravação com versão desatualizada (base para conflito em app offline).
- **Desempenho medido, não presumido.** Benchmark com volume nacional sintético e comparação com/sem índice dentro de transação desfeita: de 15x a 32x de ganho, e um predicado não sargável encontrado e corrigido no contrato.
- **Contrato estável.** Schema `api` versionado com GeoJSON e sincronização incremental; respostas reais validadas contra JSON Schema na CI; consumidor externo sem acesso ao core.
- **Documentação que não diverge.** O dicionário é gerado do catálogo; a CI falha se estiver desatualizado e o teste de estrutura falha se uma coluna nova não tiver descrição.

## Como executar

Requisitos: Docker, Python 3.11+, cliente `psql` e `make`.

```bash
cp .env.example .env          # defina a senha
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

make subir                    # PostGIS + migrações via Flyway
make testes                   # banco de teste do zero + amostra + todos os testes
make amostra                  # carrega a amostra no banco principal para explorar
make benchmark                # mede os índices (não altera o banco)
```

### Dados reais

```bash
make ibge                     # baixa e carrega cadastro e malhas do IBGE
```

O arquivo do Atlas é baixado manualmente em [atlasdigital.mdr.gov.br](https://atlasdigital.mdr.gov.br) (seção Downloads) e salvo em `data/raw/atlas/`. Depois:

```bash
make atlas-perfil ARQUIVO=data/raw/atlas/<arquivo>.xlsx   # confira o mapeamento das colunas
make atlas        ARQUIVO=data/raw/atlas/<arquivo>.xlsx
```

Se o perfil indicar campo obrigatório sem mapeamento, acrescente o nome da coluna em `etl/config/atlas_colunas.yaml`. Dados brutos não são versionados.

## Sobre a amostra

`data/sample/` é gerado por `scripts/gerar_amostra.py`. Códigos e nomes de municípios são reais; **as geometrias são retângulos fictícios e as ocorrências são inventadas**, desenhadas para que cada regra de qualidade seja exercitada exatamente uma vez. Ela existe para testes e demonstração, não para análise.

## Estrutura

```
db/migrations/     V1..V12 - estrutura, regras, cargas, contrato e permissões
etl/               carregadores (Atlas, IBGE, áreas de risco) e gerador do dicionário
tests/             testes SQL (010-060) e validação do contrato contra JSON Schema
contracts/         JSON Schema do contrato v1
scripts/           migração sem Flyway, amostra, testes, benchmark, download IBGE
docs/              artefatos de arquitetura e ADRs; docs/evidencias com saídas reais
```

## Stack

PostgreSQL 16, PostGIS 3.4, Flyway 10, Python 3 (psycopg 3, pandas), JSON Schema 2020-12, GitHub Actions.

## Autoria

Christiellen Okubo - [github.com/Christiellen](https://github.com/Christiellen)
