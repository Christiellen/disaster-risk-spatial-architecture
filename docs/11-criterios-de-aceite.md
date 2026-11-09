# 11 - Critérios de aceite, testes e homologação

Critérios técnicos para homologar entregas relacionadas a dados e integrações. Cada critério tem um teste automatizado que o comprova; a CI executa todos a cada alteração.

```bash
make testes      # recria o banco s2id_teste, aplica migrações, carrega a amostra e roda tudo
```

## Estrutura do banco

| ID | Critério | Teste |
|---|---|---|
| CA-01 | Toda tabela possui chave primária | `010_estrutura.sql` |
| CA-02 | Toda tabela e coluna de `core`, `risco` e `controle` tem descrição | `010_estrutura.sql` |
| CA-03 | Toda chave estrangeira tem índice correspondente | `010_estrutura.sql` |
| CA-04 | Toda geometria está em SIRGAS 2000 (4674) e tem índice GiST | `010_estrutura.sql` |
| CA-05 | Tabelas de histórico espelham as de origem (colunas, tipos e ordem) | `010_estrutura.sql` |
| CA-06 | O dicionário publicado corresponde ao banco | CI: regenera e compara (`git diff --exit-code`) |
| CA-07 | As migrações aplicam do zero tanto por psql quanto por Flyway | CI |

## Carga e qualidade

| ID | Dado que... | Quando... | Então... | Teste |
|---|---|---|---|---|
| CA-10 | um arquivo já carregado | é enviado novamente | nenhum lote novo é criado e nada muda | `030` |
| CA-11 | um arquivo com linhas inválidas | é carregado | as válidas entram, as inválidas vão para a quarentena com a regra e o registro original, e o lote é concluído | `030` |
| CA-12 | a amostra v1 | é carregada | 9 aceitas, 11 rejeitadas, 1 ajuste, distribuição por regra igual à esperada | `030` |
| CA-13 | um código de município com 6 dígitos e prefixo único | é carregado | é completado e o ajuste é registrado | `030` |
| CA-14 | uma coluna desconhecida no arquivo | é carregada | é preservada em `extras` e listada no lote | `030` |
| CA-15 | valores em formato brasileiro | são carregados | são interpretados corretamente | `020`, `030` |
| CA-16 | um dano informado como zero e outro vazio | são carregados | o zero é gravado e o vazio não | `030` |
| CA-17 | uma geometria inválida (laço) | é carregada | é corrigida e gravada válida | `020`, `030` |
| CA-18 | um setor de risco sem município | é carregado | o município é inferido pela maior interseção | `030` |

## Integridade no banco

| ID | Critério | Teste |
|---|---|---|
| CA-20 | Ocorrência com COBRADE que não é folha é recusada | `040` |
| CA-21 | Data de registro anterior ao evento é recusada | `040` |
| CA-22 | Contagem de pessoas fracionada é recusada | `040` |
| CA-23 | Município com prefixo de outra UF é recusado | `040` |

## Histórico e versão

| ID | Critério | Teste |
|---|---|---|
| CA-30 | Nova fotografia com dado alterado gera nova versão e evento de histórico | `040` |
| CA-31 | Nova fotografia sem alteração não gera versão | `040` |
| CA-32 | Alteração com versão desatualizada é recusada | `040` |
| CA-33 | Campos imutáveis não mudam | `040` |
| CA-34 | Exclusão gera tombstone e a consulta "as-of" reflete o passado | `040` |

## Espacial

| ID | Critério | Teste |
|---|---|---|
| CA-40 | Todas as geometrias persistidas são válidas | `050` |
| CA-41 | Todo município está contido na sua UF | `050` |
| CA-42 | Vizinhança, raio e evento regional retornam o esperado na amostra | `050` |

## Contrato e segurança

| ID | Critério | Teste |
|---|---|---|
| CA-50 | Respostas da API validam contra os JSON Schemas publicados | `validar_contrato.py` |
| CA-51 | GeoJSON filtra por caixa e prefixo COBRADE; parâmetros inválidos são recusados com erro claro | `060` |
| CA-52 | Sincronização inicial entrega todos os registros vigentes; paginação avança e termina | `060` |
| CA-53 | Consumidor externo lê o contrato e não lê `core` nem a quarentena | `060` |
| CA-54 | Analista lê o core e não escreve | `060` |

## Roteiro de homologação com dados reais

1. `make subir` e `make ibge`: conferir cerca de 5.570 municípios aceitos e nenhuma rejeição T10.
2. `make atlas-perfil ARQUIVO=...`: conferir que `cd_mun`, `dt_evento` e `cobrade` estão mapeados.
3. `make atlas ARQUIVO=...`: anotar aceitas, rejeitadas e ajustadas.
4. Revisar com a área de negócio uma amostra de cada regra em `controle.rejeicao` (aceitar a regra ou corrigir na fonte).
5. Conferir totais por UF e ano contra o painel oficial do Atlas para o mesmo período.
6. Recarregar o mesmo arquivo e confirmar que nada muda (CA-10).
