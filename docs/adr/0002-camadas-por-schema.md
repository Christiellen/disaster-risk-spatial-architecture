# ADR-0002 - Separar camadas em schemas

**Situação:** Aceito

## Contexto
Os dados chegam com formatos inconsistentes. Se a leitura já tipar e validar, uma única célula ruim derruba o arquivo inteiro, e não fica registro do que foi recusado. Ao mesmo tempo, consumidores externos não devem depender da estrutura interna.

## Alternativas
1. Carregar direto nas tabelas finais, tratando erros na aplicação.
2. Bancos separados por camada.
3. Schemas separados no mesmo banco: `staging` (texto bruto), `controle` (lotes e quarentena), `core` (modelo íntegro), `hist`, `risco`, `api`, `analitico`.

## Decisão
Opção 3. Staging aceita tudo como texto; a promoção para o core aplica as regras em uma transação por lote; o que falha vai para `controle.rejeicao` com motivo.

## Consequências
- Nenhuma linha é perdida silenciosamente; toda recusa é explicável.
- Permissões por schema implementam o menor privilégio (V12).
- Transações e integridade referencial atravessam camadas, o que não seria possível com bancos separados.
- Custo: o staging duplica temporariamente o volume do arquivo. Aceitável no volume esperado.
