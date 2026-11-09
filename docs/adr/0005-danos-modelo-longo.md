# ADR-0005 - Danos em modelo longo com catálogo de indicadores

**Situação:** Aceito

## Contexto
A fonte traz dezenas de colunas de dano (humanos, materiais, prejuízos públicos e privados), com unidades diferentes (pessoas, unidades, reais). A lista muda entre versões da fonte.

## Alternativas
1. Modelo largo: uma coluna por indicador na ocorrência.
2. EAV genérico (chave-valor sem catálogo).
3. Modelo longo `ocorrencia_dano (ocorrencia, indicador, valor)` com catálogo tipado `indicador_dano` (categoria, unidade, se compõe o total de afetados).

## Decisão
Opção 3.

## Consequências
- Novo indicador é uma linha no catálogo e um alias no YAML, sem migração de estrutura.
- Unidade explícita permite validar inteiros para pessoas e unidades (gatilho) e somar só o que é somável.
- "Não informado" (sem linha) e "zero" (linha com 0) ficam distinguíveis, o que o modelo largo com nulos confunde facilmente.
- Totais são calculados a partir do catálogo, nunca armazenados.
- Custo: análises tabulares exigem pivô. Mitigado pela visão `api.v1_ocorrencia` (danos em JSON) e pela visão materializada analítica.
- Diferente de EAV genérico: o catálogo é FK, então não existe indicador inventado.
