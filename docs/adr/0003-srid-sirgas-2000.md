# ADR-0003 - SIRGAS 2000 para armazenamento e geography para distâncias

**Situação:** Aceito

## Contexto
O IBGE publica as malhas em SIRGAS 2000, o referencial oficial do Brasil. Consultas precisam de distâncias em metros (raio de atendimento) e de relações topológicas (vizinhança). Projeções planas como UTM distorcem em um país que cobre várias zonas; Web Mercator (3857) distorce áreas.

## Alternativas
1. Armazenar em Web Mercator (3857), padrão de mapas web.
2. Armazenar em UTM por zona.
3. Armazenar em SIRGAS 2000 geográfico (4674) e usar `geography` para medidas.

## Decisão
Opção 3. Todas as colunas geométricas são `geometry(..., 4674)`. Distâncias e áreas usam cast para `geography` (cálculo geodésico), com índice GiST de expressão em `ponto_ref::geography`.

## Consequências
- Sem reprojeção na carga: o dado do IBGE entra como foi publicado.
- Medidas corretas em todo o território.
- Reprojeção para 3857 fica a cargo da camada de visualização.
- O teste 010 impede que uma migração futura crie geometria em outro SRID.
