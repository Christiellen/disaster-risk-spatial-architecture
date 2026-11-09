# ADR-0001 - Registrar decisões arquiteturais em ADRs

**Situação:** Aceito

## Contexto
Em evolução de sistemas legados, decisões de arquitetura costumam se perder em conversas e atas. Meses depois ninguém sabe por que o modelo é como é, e alternativas já descartadas voltam a ser discutidas.

## Alternativas
1. Documento único de arquitetura atualizado continuamente.
2. Wiki externa.
3. ADRs curtos versionados junto com o código.

## Decisão
Opção 3. Cada ADR registra contexto, alternativas, decisão e consequências, e é revisado no mesmo pull request que implementa a decisão.

## Consequências
- O histórico da decisão acompanha o histórico do código.
- Mudança de decisão gera novo ADR, nunca edição silenciosa do antigo.
