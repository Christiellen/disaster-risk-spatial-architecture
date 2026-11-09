# ADR-0006 - Chave natural (protocolo ou hash) e chave substituta interna

**Situação:** Aceito

## Contexto
Cargas precisam ser idempotentes (recarregar não duplica) e consumidores externos precisam de identificadores estáveis. O protocolo do S2iD é o identificador natural, mas nem todo registro da fonte o traz.

## Alternativas
1. Só chave substituta: recarga gera duplicatas.
2. Só protocolo: registros sem protocolo ficam de fora.
3. `chave_origem` = protocolo quando existe; senão `H:` + SHA-256 de (município, COBRADE, data do evento). Chave substituta `bigint identity` para FKs internas.

## Decisão
Opção 3. O contrato público expõe apenas `chave_origem`.

## Consequências
- Recarga idempotente via `ON CONFLICT (chave_origem)`.
- Duas ocorrências do mesmo tipo, no mesmo município e dia, sem protocolo, colidem e a segunda é rejeitada como duplicada (R11). Na prática do S2iD esse caso é um único registro.
- Se um registro ganhar protocolo depois, a chave muda e haveria duplicidade (risco RT-02, pendência P-05).
- Reprocessar do zero produz os mesmos identificadores públicos, o que não aconteceria expondo a chave substituta.
