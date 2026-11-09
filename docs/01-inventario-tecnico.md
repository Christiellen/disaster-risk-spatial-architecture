# 01 - Inventário técnico de bases, modelos e insumos

Primeiro artefato da Fase 0: o que existe, onde está, em que formato, com que qualidade aparente e quem é o dono. Nada é modelado antes deste levantamento.

## Fontes de dados

| ID | Fonte | Mantenedor | Conteúdo | Formato | Acesso | Granularidade | Atualização | Papel no modelo |
|---|---|---|---|---|---|---|---|---|
| F1 | Atlas Digital de Desastres no Brasil | Sedec/MIDR, com Ceped/UFSC | Registros de desastres por município, classificados pela COBRADE, com danos humanos, materiais e prejuízos | Planilha/CSV baixada no portal | Público, download manual em atlasdigital.mdr.gov.br | Ocorrência x município | Periódica (série desde 1991) | Ocorrências e danos (`core.ocorrencia`, `core.ocorrencia_dano`) |
| F2 | API de Localidades do IBGE | IBGE | Cadastro de municípios, UFs e regiões | JSON (`?view=nivelado`) | Público, API REST | Município | Quando há criação/alteração de município | `core.municipio`, `core.uf`, `core.regiao` |
| F3 | API de Malhas do IBGE (v3) | IBGE | Limites municipais e estaduais | GeoJSON, SIRGAS 2000 | Público, API REST | Polígono por município/UF | Por edição da malha | `core.municipio.geom`, `core.uf.geom` |
| F4 | Setorização de áreas de risco | Serviço Geológico do Brasil (SGB) | Setores de risco geológico/hidrológico por município | Shapefile/KML, convertido para GeoJSON | Público, por município | Polígono por setor | Por campanha de mapeamento | `risco.area_risco` (opcional) |
| F5 | COBRADE | Sedec/MIDR (norma) | Classificação hierárquica de desastres | Anexo normativo | Público | Código de 5 dígitos | Por revisão normativa | `core.cobrade` (carga inicial na migração V4) |

> Termos de uso e licenças de cada fonte devem ser conferidos antes de redistribuir dados. Por isso `data/raw/` não é versionado: o repositório guarda o **código** que reproduz a carga, não os dados oficiais.

## Insumos do repositório

| Insumo | Onde | Observação |
|---|---|---|
| Amostra sintética | `data/sample/` | Códigos de município reais; geometrias fictícias; ocorrências inventadas para exercitar cada regra. Não usar para análise. |
| Mapeamento de colunas do Atlas | `etl/config/atlas_colunas.yaml` | Aliases de cabeçalho -> nomes canônicos. Ajustável sem mudar código. |
| Migrações | `db/migrations/V1..V12` | Fonte única da estrutura do banco. |
| Contratos | `contracts/*.schema.json` | JSON Schema do que a API entrega. |

## Perfilamento

O carregador do Atlas tem modo de perfil que **não toca no banco** e descreve o arquivo: colunas encontradas, destino de cada uma, percentual de vazios, cardinalidade, exemplos e formatos de data presentes.

```bash
python3 -m etl.carregar_atlas --arquivo data/raw/atlas/<arquivo>.xlsx --perfil
```

Exemplo real sobre a amostra: [`evidencias/perfil_atlas_amostra.md`](evidencias/perfil_atlas_amostra.md). O perfil já evidencia problemas que viram regras na carga (ver [06](06-regras-de-integridade.md)):

- datas em **três formatos** no mesmo arquivo (dd/mm/aaaa, ISO e número de série do Excel);
- COBRADE em formatos diferentes (`12100`, `1.3.2.1.4`, `12200 - Enxurradas`);
- valores numéricos no padrão brasileiro (`12.345.678,90`) misturados a inteiros simples;
- colunas sem mapeamento conhecido (`setores_censitarios`), que são **preservadas**, não descartadas.

## Lacunas identificadas no inventário

| Lacuna | Impacto | Encaminhamento |
|---|---|---|
| Dicionário oficial das colunas do Atlas não localizado junto ao download | Interpretação de colunas depende de inferência | Pendência P-04; o perfil e o mapeamento YAML tornam a inferência explícita e revisável |
| COBRADE categoria Tecnológico não carregada | Ocorrências tecnológicas são rejeitadas (R04) | Pendência P-01 |
| Domínio do campo "situação" desconhecido | Não é possível fechar com FK | Pendência P-02; campo mantido como texto até o perfilamento da base completa |
| Fonte não informa exclusões entre versões do arquivo | Registro removido na fonte permanece no core | Pendência P-03 |
