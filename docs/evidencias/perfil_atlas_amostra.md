# Perfil do arquivo

Linhas de dados: 20

| Coluna no arquivo | Destino | % vazio | Distintos | Exemplos |
|---|---|---|---|---|
| protocolo | protocolo | 10.0 | 18 | SC-F-4205407-12100-20230115, SC-F-4216602-12100-20230115, SC |
| uf | uf | 5.0 | 6 | SC, RS, DF |
| cod_ibge_mun | cd_mun | 5.0 | 10 | 4205407, 4216602, 4211900 |
| nome_municipio | nome_mun | 5.0 | 10 | Florianópolis, São José, Palhoça |
| data_evento | dt_evento | 0.0 | 18 | 15/01/2023, 02/03/2022, 2023-01-15 |
| data_registro | dt_registro | 5.0 | 19 | 16/01/2023, 03/03/2022, 2023-01-17 |
| cod_cobrade | cobrade | 0.0 | 9 | 12100, 1.3.2.1.4, 12200 - Enxurradas |
| descricao_tipologia | cobrade_desc | 0.0 | 9 | Inundações, Chuvas intensas, Enxurradas |
| status | situacao | 5.0 | 3 | Reconhecido, Em análise |
| dh_mortos | dano:DH_MORTOS | 65.0 | 5 | 0, 1, 5 |
| dh_feridos | dano:DH_FERIDOS | 55.0 | 9 | 3, 1, 4 |
| dh_enfermos | dano:DH_ENFERMOS | 90.0 | 3 | 30, 0 |
| dh_desabrigados | dano:DH_DESABRIGADOS | 55.0 | 9 | 40, 10, 15 |
| dh_desalojados | dano:DH_DESALOJADOS | 55.0 | 9 | 120, 25, 60 |
| dh_desaparecidos | dano:DH_DESAPARECIDOS | 80.0 | 3 | 0, 2 |
| dh_outros_afetados | dano:DH_OUTROS_AFETADOS | 70.0 | 6 | 800, 300, 160.000 |
| dm_uni_habita_danificadas | dano:DM_UH_DANIFICADAS | 55.0 | 9 | 35, 8, 20 |
| dm_uni_habita_destruidas | dano:DM_UH_DESTRUIDAS | 70.0 | 6 | 2, 3, 310 |
| pepl_total_publico | dano:PEPL_TOTAL | 80.0 | 5 | 1.250.000,00, 500.000,00, 12.345.678,90 |
| pepr_total_privado | dano:PEPR_TOTAL | 80.0 | 5 | 3.400.000,00, 900.000,00, 98.765.432,10 |
| setores_censitarios | extras (não mapeada) | 95.0 | 2 | 12;13 |

Formatos de data do evento: {'dd/mm/aaaa': 18, 'aaaa-mm-dd': 1, 'série Excel': 1}
