# 10 - Riscos técnicos, pendências e recomendações de evolução

## Matriz de riscos técnicos

Probabilidade e impacto: B (baixo), M (médio), A (alto).

| ID | Risco | Prob. | Impacto | Mitigação adotada | Ação recomendada |
|---|---|:-:|:-:|---|---|
| RT-01 | Mudança de layout do arquivo do Atlas (colunas renomeadas) | A | M | Mapeamento externo em YAML; perfil antes da carga; carga aborta se faltar campo obrigatório; colunas novas preservadas em `extras` | Rodar `--perfil` a cada novo arquivo e versionar o YAML |
| RT-02 | Registro sem protocolo ganha protocolo numa versão futura do arquivo | M | M | Chave por hash documentada (ADR-0006) | Rotina de reconciliação: ao surgir protocolo para (município, COBRADE, data) já existente com chave `H:`, migrar a chave em vez de criar novo registro |
| RT-03 | Ambiguidade numérica `1.234` (mil e duzentos ou 1,234?) | M | M | Interpretado como padrão brasileiro; indicadores de pessoas exigem inteiro, o que expõe a maioria dos erros | Ler a planilha com tipos nativos quando o arquivo for XLSX e o valor vier numérico |
| RT-04 | Exclusões na fonte não detectadas (fotografia sem o registro) | M | M | Nenhuma: o registro permanece | Pendência P-03 |
| RT-05 | Cursor por `hist_id` pode pular evento de transação longa que confirma depois de outra mais recente | B | A | Cargas são serializadas por lote | Em escrita concorrente real, entregar só eventos com `hist_registrado_em < now() - margem` ou usar `pg_current_snapshot()`/`xmin` como cursor |
| RT-06 | Divergência entre `hist.*` e `core.*` após migração | M | A | Teste 010 compara colunas, tipos e ordem | Toda migração que altera tabela auditada altera também a de histórico |
| RT-07 | Crescimento além do previsto | B | M | Índices dimensionados para centenas de milhares de linhas | Particionar por ano de evento acima de dezenas de milhões de linhas |
| RT-08 | Malha municipal desatualizada (município novo) | B | M | Rejeição R02 visível na quarentena | Recarregar cadastro e malha do IBGE antes de cada carga anual do Atlas |
| RT-09 | COBRADE transcrita com erro na carga inicial | M | A | Árvore validada por constraints de estrutura | Conferir contra o anexo normativo vigente antes de uso real (P-01) |
| RT-10 | Crescimento do changelog | M | B | Índices por chave e tempo | Política de retenção/arquivamento de `hist.*` definida com a área de negócio |
| RT-11 | Exposição indevida de dados | B | A | Papéis com menor privilégio; consumidor só vê `api` (teste 060) | Revisar se algum campo futuro contém dado pessoal antes de expô-lo |

## Pendências

| ID | Pendência | Dono sugerido | Bloqueia |
|---|---|---|---|
| P-01 | Completar a categoria Tecnológico da COBRADE e conferir a árvore inteira contra o anexo normativo vigente | Arquitetura de dados + área de negócio | Ocorrências tecnológicas (hoje rejeitadas em R04) |
| P-02 | Fechar o domínio de `situacao` após perfilar a base completa; transformar em tabela de domínio com FK | Arquitetura de dados | Filtros confiáveis por situação |
| P-03 | Definir política para registros ausentes em nova fotografia da fonte (exclusão lógica? alerta?) | Área de negócio | Paridade exata com a fonte |
| P-04 | Obter o dicionário oficial das colunas do Atlas e revisar o mapeamento YAML | Arquitetura de dados | Interpretação definitiva de colunas |
| P-05 | Definir regra de conciliação de chaves `H:` com protocolos novos (RT-02) | Arquitetura de dados | Duplicidade em reprocessamentos |

## Recomendações de evolução

1. **Áreas de risco reais**: carregar a setorização do SGB para os municípios prioritários e cruzar com recorrência (consulta em [09](09-consultas-espaciais.md)).
2. **Exposição via API HTTP**: publicar o schema `api` com PostgREST ou `pg_featureserv` (OGC API Features), sem reimplementar regras fora do banco.
3. **Tiles vetoriais**: `ST_AsMVT` para mapas com muitos municípios no app.
4. **Qualidade contínua**: painel sobre `controle.lote_carga` e `controle.rejeicao` com taxa de rejeição por regra e por lote.
5. **População**: integrar estimativas populacionais do IBGE para indicadores relativos (afetados por mil habitantes).
