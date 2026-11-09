"""Gera os dados de amostra em data/sample/.

A amostra serve para testes automatizados e demonstração SEM depender de
download. Códigos e nomes de municípios são reais (cadastro público do IBGE);
as GEOMETRIAS SÃO FICTÍCIAS (retângulos aproximados) e as OCORRÊNCIAS SÃO
SINTÉTICAS, construídas para exercitar cada regra de qualidade.
Não use a amostra para qualquer conclusão sobre desastres reais.
"""

import csv
import json
from pathlib import Path

DESTINO = Path(__file__).resolve().parent.parent / "data" / "sample"

MUNICIPIOS = [
    # cd_mun, nome, cd_uf, sigla, nome_uf, regiao, (xmin, ymin, xmax, ymax)
    ("4205407", "Florianópolis", 42, "SC", "Santa Catarina", "S", (-48.60, -27.70, -48.40, -27.50)),
    ("4216602", "São José", 42, "SC", "Santa Catarina", "S", (-48.80, -27.70, -48.60, -27.50)),
    ("4211900", "Palhoça", 42, "SC", "Santa Catarina", "S", (-48.80, -27.90, -48.60, -27.70)),
    ("4314902", "Porto Alegre", 43, "RS", "Rio Grande do Sul", "S", (-51.30, -30.25, -51.05, -29.95)),
    ("4304606", "Canoas", 43, "RS", "Rio Grande do Sul", "S", (-51.30, -29.95, -51.05, -29.85)),
    ("5300108", "Brasília", 53, "DF", "Distrito Federal", "CO", (-48.30, -16.05, -47.30, -15.50)),
    ("3304557", "Rio de Janeiro", 33, "RJ", "Rio de Janeiro", "SE", (-43.80, -23.10, -43.10, -22.75)),
    ("2927408", "Salvador", 29, "BA", "Bahia", "NE", (-38.55, -13.02, -38.30, -12.75)),
]

UFS = {
    42: (-49.00, -28.00, -48.30, -27.40),
    43: (-51.50, -30.40, -50.90, -29.70),
    53: (-48.30, -16.05, -47.30, -15.50),
    33: (-44.00, -23.20, -42.90, -22.60),
    29: (-38.70, -13.20, -38.20, -12.60),
}


def retangulo(caixa):
    x0, y0, x1, y1 = caixa
    return {"type": "Polygon", "coordinates": [[[x0, y0], [x1, y0], [x1, y1], [x0, y1], [x0, y0]]]}


def municipios_json():
    linhas = [{"municipio-id": int(c), "municipio-nome": n, "UF-id": u, "UF-sigla": s,
               "UF-nome": un, "regiao-sigla": r} for c, n, u, s, un, r, _ in MUNICIPIOS]
    # Registro defeituoso proposital: código com 5 dígitos (regra T01)
    linhas.append({"municipio-id": 12345, "municipio-nome": "Registro defeituoso", "UF-id": 12,
                   "UF-sigla": "AC", "UF-nome": "Acre", "regiao-sigla": "N"})
    return linhas


def malha_mun():
    feicoes = [{"type": "Feature", "properties": {"codarea": c}, "geometry": retangulo(cx)}
               for c, *_, cx in MUNICIPIOS]
    # Polígono em laço ("gravata"), inválido: deve ser corrigido por ST_MakeValid.
    feicoes[-1]["geometry"] = {"type": "Polygon", "coordinates": [[
        [-38.55, -13.02], [-38.30, -12.75], [-38.30, -13.02], [-38.55, -12.75], [-38.55, -13.02]]]}
    # Feição sem cadastro correspondente (regra T11)
    feicoes.append({"type": "Feature", "properties": {"codarea": "9999999"},
                    "geometry": retangulo((-60.0, -10.0, -59.9, -9.9))})
    return {"type": "FeatureCollection", "features": feicoes}


def malha_uf():
    return {"type": "FeatureCollection", "features": [
        {"type": "Feature", "properties": {"codarea": str(u)}, "geometry": retangulo(cx)} for u, cx in UFS.items()]}


CABECALHO = ["Protocolo", "UF", "Cód. IBGE Mun", "Nome Município", "Data Evento", "Data Registro",
             "Cód. Cobrade", "Descrição Tipologia", "Status", "DH_MORTOS", "DH_FERIDOS", "DH_ENFERMOS",
             "DH_DESABRIGADOS", "DH_DESALOJADOS", "DH_DESAPARECIDOS", "DH_OUTROS_AFETADOS",
             "DM_Uni_Habita_Danificadas", "DM_Uni_Habita_Destruidas", "PEPL_Total_Publico",
             "PEPR_Total_Privado", "Setores Censitários"]

# (protocolo, uf, cd_mun, nome, dt_evento, dt_registro, cobrade, desc, status,
#  mortos, feridos, enfermos, desabrigados, desalojados, desaparecidos, outros,
#  uh_danif, uh_destr, pepl, pepr, setores)   -> comentário = resultado esperado
OCORRENCIAS = [
    ("SC-F-4205407-12100-20230115", "SC", "4205407", "Florianópolis", "15/01/2023", "16/01/2023", "12100", "Inundações", "Reconhecido",
     "0", "3", "", "40", "120", "0", "800", "35", "2", "1.250.000,00", "3.400.000,00", "12;13"),          # aceita
    ("", "SC", "4205407", "Florianópolis", "02/03/2022", "03/03/2022", "1.3.2.1.4", "Chuvas intensas", "Reconhecido",
     "", "", "", "10", "25", "", "", "8", "", "", "", ""),                                                    # aceita, chave por hash
    ("SC-F-4216602-12100-20230115", "SC", "4216602", "São José", "2023-01-15", "2023-01-17", "12100", "Inundações", "Reconhecido",
     "0", "1", "", "15", "60", "", "300", "20", "", "500.000,00", "900.000,00", ""),                        # aceita (vizinho, mesmo evento)
    ("SC-F-4211900-12200-20230117", "SC", "4211900", "Palhoça", "17/01/2023", "18/01/2023", "12200 - Enxurradas", "Enxurradas", "Em análise",
     "1", "4", "", "22", "90", "", "", "12", "3", "", "", ""),                                                # aceita
    ("RS-F-4314902-12100-20240502", "RS", "4314902", "Porto Alegre", "02/05/2024", "03/05/2024", "12100", "Inundações", "Reconhecido",
     "5", "120", "30", "15.432", "78.900", "2", "160.000", "4.200", "310", "12.345.678,90", "98.765.432,10", ""),  # aceita
    ("RS-F-4304606-12100-20240502", "RS", "4304606", "Canoas", "02/05/2024", "04/05/2024", "12100", "Inundações", "Reconhecido",
     "3", "40", "", "8.100", "42.000", "", "", "2.100", "150", "", "", ""),                                    # aceita
    ("DF-F-5300108-14110-20240815", "DF", "530010", "Brasília", "15/08/2024", "20/08/2024", "14110", "Estiagem", "Reconhecido",
     "", "", "", "", "", "", "250000", "", "", "", "", ""),                                                   # aceita com ajuste (6 dígitos)
    ("XX-F-9999999-12100-20230101", "SC", "9999999", "Inexistente", "01/01/2023", "02/01/2023", "12100", "Inundações", "Reconhecido",
     "", "", "", "", "", "", "", "", "", "", "", ""),                                                         # R02
    ("RJ-F-2927408-13213-20230601", "RJ", "2927408", "Salvador", "01/06/2023", "02/06/2023", "13213", "Granizo", "Reconhecido",
     "", "", "", "", "", "", "", "", "", "", "", ""),                                                         # R03
    ("SC-F-4205407-12000-20230201", "SC", "4205407", "Florianópolis", "01/02/2023", "02/02/2023", "12000", "Hidrológico", "Reconhecido",
     "", "", "", "", "", "", "", "", "", "", "", ""),                                                         # R05
    ("RJ-F-3304557-22210-20230301", "RJ", "3304557", "Rio de Janeiro", "01/03/2023", "02/03/2023", "22210", "Tecnológico", "Reconhecido",
     "", "", "", "", "", "", "", "", "", "", "", ""),                                                         # R04
    ("RJ-F-3304557-13215-20200231", "RJ", "3304557", "Rio de Janeiro", "31/02/2020", "01/03/2020", "13215", "Vendaval", "Reconhecido",
     "", "", "", "", "", "", "", "", "", "", "", ""),                                                         # R06
    ("RJ-F-3304557-13215-20310101", "RJ", "3304557", "Rio de Janeiro", "01/01/2031", "02/01/2031", "13215", "Vendaval", "Reconhecido",
     "", "", "", "", "", "", "", "", "", "", "", ""),                                                         # R07
    ("RS-F-4314902-13215-20230910", "RS", "4314902", "Porto Alegre", "10/09/2023", "05/09/2023", "13215", "Vendaval", "Reconhecido",
     "", "", "", "", "", "", "", "", "", "", "", ""),                                                         # R08
    ("SC-F-4216602-12300-20230401", "SC", "4216602", "São José", "01/04/2023", "02/04/2023", "12300", "Alagamentos", "Reconhecido",
     "", "-5", "", "", "", "", "", "", "", "", "", ""),                                                       # R10 (negativo)
    ("SC-F-4211900-12300-20230402", "SC", "4211900", "Palhoça", "02/04/2023", "03/04/2023", "12300", "Alagamentos", "Reconhecido",
     "", "", "", "2,5", "", "", "", "", "", "", "", ""),                                                      # R10 (pessoa fracionada)
    ("SC-F-4205407-12100-20230115", "SC", "4205407", "Florianópolis", "15/01/2023", "16/01/2023", "12100", "Inundações", "Reconhecido",
     "0", "3", "", "40", "120", "0", "800", "35", "2", "", "", ""),                                           # R11 (duplicada)
    ("BA-F-2927408-13213-20240101", "BA", "2927408", "Salvador", "45292", "45293", "13213", "Granizo", "Reconhecido",
     "", "2", "", "", "5", "", "", "14", "", "", "", ""),                                                     # aceita (data em série Excel)
    ("rj-f-3304557-13215-20240120", "RJ", "3304557", "Rio de Janeiro", "20/01/2024", "21/01/2024", "13215", "Vendaval", "Reconhecido",
     "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", "0", ""),                                              # aceita (protocolo normalizado, zeros)
    ("", "", "", "", "05/05/2023", "", "12100", "Inundações", "", "", "", "", "", "", "", "", "", "", "", "", ""),  # R01
]

EXPECTATIVA = {"aceitas": 9, "ajustadas": 1, "R01_MUN_AUSENTE": 1, "R02_MUN_INEXISTENTE": 1,
               "R03_UF_DIVERGENTE": 1, "R04_COBRADE_INEXISTENTE": 1, "R05_COBRADE_NAO_FOLHA": 1,
               "R06_DATA_EVENTO_INVALIDA": 1, "R07_DATA_EVENTO_FUTURA": 1,
               "R08_REGISTRO_ANTES_DO_EVENTO": 1, "R10_DANO_INVALIDO": 2, "R11_DUPLICADO_NO_LOTE": 1}


def atlas(caminho: Path, linhas):
    with open(caminho, "w", newline="", encoding="utf-8") as f:
        # Duas linhas de título antes do cabeçalho, como em planilhas oficiais
        f.write("Atlas Digital de Desastres no Brasil - AMOSTRA SINTÉTICA\n")
        f.write("Gerado por scripts/gerar_amostra.py - não representa desastres reais\n")
        w = csv.writer(f, delimiter=";")
        w.writerow(CABECALHO)
        w.writerows(linhas)


def areas_risco():
    return {"type": "FeatureCollection", "features": [
        {"type": "Feature", "properties": {"ID_SETOR": "SC-FLN-001", "GRAU": "Muito Alto",
                                           "TIPOLOGIA": "Deslizamento planar", "COBRADE": "11321"},
         "geometry": retangulo((-48.55, -27.65, -48.50, -27.60))},
        {"type": "Feature", "properties": {"ID_SETOR": "RS-POA-001", "GRAU": "R3",
                                           "TIPOLOGIA": "Inundação", "COBRADE": "12100", "GEOCODIGO": "4314902"},
         "geometry": retangulo((-51.25, -30.10, -51.15, -30.00))},
        {"type": "Feature", "properties": {"ID_SETOR": "RS-POA-002", "GRAU": "Crítico",
                                           "TIPOLOGIA": "Inundação"},
         "geometry": retangulo((-51.20, -30.20, -51.10, -30.15))},                       # G03
        {"type": "Feature", "properties": {"ID_SETOR": "SC-PLH-001", "GRAU": "Alto",
                                           "TIPOLOGIA": "Enxurrada", "COBRADE": "12200"},
         "geometry": {"type": "Polygon", "coordinates": [[                                   # laço, corrigido
             [-48.75, -27.85], [-48.65, -27.75], [-48.65, -27.85], [-48.75, -27.75], [-48.75, -27.85]]]}},
    ]}


def main():
    DESTINO.mkdir(parents=True, exist_ok=True)
    (DESTINO / "ibge_municipios_amostra.json").write_text(json.dumps(municipios_json(), ensure_ascii=False, indent=1), encoding="utf-8")
    (DESTINO / "ibge_malha_mun_amostra.json").write_text(json.dumps(malha_mun()), encoding="utf-8")
    (DESTINO / "ibge_malha_uf_amostra.json").write_text(json.dumps(malha_uf()), encoding="utf-8")
    (DESTINO / "areas_risco_amostra.geojson").write_text(json.dumps(areas_risco(), ensure_ascii=False), encoding="utf-8")
    atlas(DESTINO / "atlas_amostra_v1.csv", OCORRENCIAS)

    # v2: nova fotografia da mesma base. Florianópolis teve desabrigados revisados
    # e perdeu o prejuízo privado; Salvador ganhou um registro novo.
    v2 = [list(l) for l in OCORRENCIAS]
    v2[0][12], v2[0][19] = "55", ""
    v2.append(["BA-F-2927408-12300-20240310", "BA", "2927408", "Salvador", "10/03/2024", "11/03/2024", "12300",
               "Alagamentos", "Reconhecido", "", "", "", "12", "40", "", "", "6", "", "", "", ""])
    atlas(DESTINO / "atlas_amostra_v2.csv", v2)
    (DESTINO / "expectativa_amostra_v1.json").write_text(json.dumps(EXPECTATIVA, indent=1), encoding="utf-8")
    print(f"Amostra gerada em {DESTINO}")


if __name__ == "__main__":
    main()
