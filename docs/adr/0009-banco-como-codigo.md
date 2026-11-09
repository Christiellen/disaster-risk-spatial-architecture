# ADR-0009 - Banco como código: migrações, testes e dicionário gerado

**Situação:** Aceito

## Contexto
A principal lacuna em ambientes legados é a divergência entre documentação e implementação: o diagrama diz uma coisa, o banco faz outra. Também é comum o banco de produção ter alterações manuais sem registro.

## Alternativas
1. Scripts DDL avulsos e documentação mantida à mão.
2. ORM gerando o esquema.
3. Migrações SQL versionadas (Flyway), testes escritos em SQL contra o banco real e dicionário de dados gerado a partir dos `COMMENT ON`.

## Decisão
Opção 3.

## Consequências
- O banco é reconstruível do zero em qualquer ambiente com um comando.
- O dicionário não pode divergir: a CI regenera e falha se houver diferença.
- O teste 010 obriga a documentar toda tabela e coluna nova.
- Testes de regra rodam onde a regra está (no banco), sem mocks.
- Migrações publicadas são imutáveis; correções entram como nova versão.
- O script `aplicar_migracoes.sh` permite rodar sem Flyway; a CI valida os dois caminhos.
