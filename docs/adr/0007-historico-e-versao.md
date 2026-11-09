# ADR-0007 - Changelog por gatilho e concorrência otimista

**Situação:** Aceito

## Contexto
Três necessidades: auditar alterações de dados oficiais, consultar como um registro estava em uma data e alimentar a sincronização de um app que trabalha offline. Além disso, o app pode tentar gravar sobre dado que mudou enquanto estava desconectado.

## Alternativas
1. Colunas de validade (SCD tipo 2) na própria tabela.
2. Tabelas temporais via extensão.
3. Changelog em `hist.*` alimentado por gatilho genérico + coluna `versao` com verificação otimista.

## Decisão
Opção 3. O gatilho grava a imagem da linha a cada INSERT/UPDATE e a imagem anterior em DELETE. Um gatilho BEFORE UPDATE incrementa `versao` e recusa a gravação se a versão informada não for a atual.

## Consequências
- A tabela do core continua simples e com uma linha por ocorrência (sem filtros de vigência em toda consulta).
- Um único mecanismo serve auditoria, "as-of" e sincronização.
- Sem dependência de extensão além do PostGIS.
- Recarga idêntica não gera versão (upsert com `IS DISTINCT FROM`), então o histórico só registra mudança real.
- Custo: a tabela de histórico precisa acompanhar a estrutura da origem; o teste 010 falha se divergirem.
