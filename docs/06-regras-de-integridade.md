# 06 - Regras de integridade, histórico, versionamento e rastreabilidade

A integridade é garantida em **duas camadas**:

1. **Na carga** (funções `fn_processar_lote_*`): cada linha é avaliada, e a que viola uma regra vai para a quarentena com o motivo, sem derrubar o lote.
2. **No banco** (constraints e gatilhos): mesmo quem escreve fora da carga não consegue gravar dado inconsistente.

## Catálogo de regras da carga

### Ocorrências (Atlas) - prefixo R

A primeira regra violada é a registrada, na ordem abaixo.

| Regra | Condição de rejeição | Por que importa |
|---|---|---|
| R01_MUN_AUSENTE | Código do município vazio | Ocorrência sem território não é localizável |
| R02_MUN_INEXISTENTE | Código não existe no cadastro do IBGE (nem completável) | Evita município fantasma |
| R03_UF_DIVERGENTE | UF informada difere da UF do município | Sinal de erro de digitação no código ou na UF |
| R04_COBRADE_INEXISTENTE | Código não encontrado na árvore COBRADE | Classificação inválida |
| R05_COBRADE_NAO_FOLHA | Código é grupo/subgrupo/tipo com filhos | Classificação genérica demais para análise |
| R06_DATA_EVENTO_INVALIDA | Data ausente ou impossível (ex.: 31/02) | Série temporal confiável |
| R07_DATA_EVENTO_FUTURA | Data do evento posterior à data da carga | Erro de digitação de ano |
| R08_REGISTRO_ANTES_DO_EVENTO | Registro anterior ao evento | Incoerência temporal |
| R09_PROTOCOLO_FORMATO | Protocolo fora do padrão alfanumérico | Chave natural confiável |
| R10_DANO_INVALIDO | Valor não numérico, negativo ou fracionado em indicador de pessoas/unidades | Totais confiáveis |
| R11_DUPLICADO_NO_LOTE | Mesma chave de outra linha válida do arquivo (mantém a primeira) | Evita dupla contagem |

### Território (IBGE) - prefixo T

| Regra | Condição |
|---|---|
| T01_MUN_CODIGO_INVALIDO | Código sem 7 dígitos |
| T02_MUN_NOME_AUSENTE | Nome vazio |
| T03_UF_CODIGO_INVALIDO | Código da UF sem 2 dígitos |
| T04_MUN_PREFIXO_UF | Prefixo do município diferente da UF |
| T05_REGIAO_INVALIDA | Sigla de região desconhecida |
| T10_GEOMETRIA_INVALIDA | Geometria irrecuperável mesmo após `ST_MakeValid` |
| T11_MALHA_SEM_CADASTRO | Feição de malha sem município/UF correspondente |

### Áreas de risco - prefixo G

| Regra | Condição |
|---|---|
| G01_ID_EXTERNO_AUSENTE | Setor sem identificador na fonte |
| G02_GEOMETRIA_INVALIDA | Geometria irrecuperável ou não poligonal |
| G03_GRAU_RISCO_DESCONHECIDO | Grau fora de Baixo/Médio/Alto/Muito Alto ou R1-R4 |
| G04_MUN_INEXISTENTE | Geocódigo informado não existe |
| G05_COBRADE_INEXISTENTE | COBRADE relacionado não existe |

### Ajustes automáticos - prefixo A

Correções aplicadas **somente** quando o resultado é inequívoco, sempre registradas em `controle.ajuste` com valor original e ajustado.

| Regra | Ajuste |
|---|---|
| A01_MUN_6_DIGITOS_COMPLETADO | Código de 6 dígitos (sem dígito verificador) completado quando existe exatamente um município com esse prefixo |

Normalizações silenciosas (sem registro de ajuste, porque não alteram o significado): aparar espaços, protocolo em maiúsculas, `.0` de planilha no código, formatos de data e número.

## Constraints no core (independentes da carga)

| Objeto | Regra |
|---|---|
| `core.municipio` | Código com 7 dígitos; prefixo = UF; geometria válida |
| `core.uf` | Código entre 11 e 53; região coerente com o primeiro dígito |
| `core.cobrade` | Só a raiz não tem pai; filho pertence à mesma categoria do pai |
| `core.ocorrencia` | COBRADE folha (FK composta); registro >= evento; evento >= 1900; protocolo com formato válido; `atualizado_em >= criado_em` |
| `core.ocorrencia_dano` | Valor >= 0; inteiro para PESSOAS/UNIDADES (gatilho) |
| `risco.area_risco` | Geometria válida e não vazia; grau no domínio |
| `controle.lote_carga` | Hash SHA-256 válido; lote PROCESSADO tem contagens coerentes |

Todas estão no [dicionário](05-dicionario-de-dados.md) e são exercitadas pelo teste `tests/sql/040_historico_e_versao.sql`.

## Histórico

- `hist.ocorrencia` e `hist.ocorrencia_dano` recebem, por gatilho, a imagem da linha em cada inclusão, alteração e exclusão (tombstone).
- Metadados: operação, instante da transação e papel de banco que executou.
- `hist.fn_ocorrencia_em(chave, instante)` reconstrói a ocorrência como estava em qualquer momento.
- O teste 010 verifica que as tabelas de histórico continuam espelhando as de origem após qualquer migração.

## Versionamento e concorrência

- Cada ocorrência tem `versao`, incrementada pelo gatilho a cada alteração real.
- **Recarga sem mudança não gera versão** (upsert com `IS DISTINCT FROM`).
- Alteração em dano gera nova versão da ocorrência (no máximo uma por transação).
- **Concorrência otimista**: quem altera informa a versão que leu. Se outro processo alterou antes, a gravação é recusada com `serialization_failure`. É o mecanismo que permite ao app offline detectar conflito ao sincronizar.
- Campos imutáveis (`id_ocorrencia`, `chave_origem`, `criado_em`) são protegidos pelo gatilho.

## Rastreabilidade

Qualquer número exposto pode ser seguido até a origem:

```sql
SELECT o.chave_origem, l.arquivo, l.hash_sha256, o.linha_origem, l.iniciado_em
FROM core.ocorrencia o
JOIN controle.lote_carga l ON l.id_lote = o.id_lote_origem
WHERE o.chave_origem = 'RS-F-4314902-12100-20240502';
```

E qualquer linha recusada pode ser explicada:

```sql
SELECT linha_origem, regra, detalhe, registro
FROM controle.rejeicao
WHERE id_lote = :lote
ORDER BY regra, linha_origem;
```

Resultado da amostra: [`evidencias/rejeicoes_amostra.txt`](evidencias/rejeicoes_amostra.txt).
