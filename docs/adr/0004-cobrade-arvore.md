# ADR-0004 - COBRADE como árvore; só folhas classificam

**Situação:** Aceito

## Contexto
A COBRADE tem até cinco níveis, mas não é uniforme: "Inundações" (12100) é folha no nível de subgrupo, enquanto "Chuvas intensas" (13214) é folha no nível de subtipo. Ocorrências classificadas em nós intermediários ("Hidrológico") perdem precisão analítica.

## Alternativas
1. Cinco colunas fixas (grupo, subgrupo, tipo, subtipo) na ocorrência.
2. Uma tabela por nível.
3. Tabela única autorreferenciada com marcação de folha.

## Decisão
Opção 3, com a restrição implementada como **FK composta**: a ocorrência tem `cobrade_classificavel` fixo em `true` e referencia `cobrade (cd_cobrade, classificavel)`. Assim, apontar para um nó que não é folha viola a FK.

## Consequências
- A regra vale para qualquer escrita, não só para a carga, e sem gatilho.
- A hierarquia achatada fica disponível em `core.vw_cobrade_hierarquia` (CTE recursiva).
- Códigos descontinuados são desativados (`ativo = false`), nunca apagados, para não quebrar o histórico.
- Custo: uma coluna técnica constante na ocorrência. Documentada no dicionário.
