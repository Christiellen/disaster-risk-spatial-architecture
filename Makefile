# Atalhos. Requer: Docker, Python 3.11+, cliente psql. Variáveis do libpq vêm do .env.
-include .env
export

.PHONY: ajuda subir migrar amostra testes dicionario benchmark ibge atlas-perfil atlas parar

ajuda:
	@echo "make subir        - sobe o PostGIS e aplica as migrações (Flyway)"
	@echo "make amostra      - carrega a amostra sintética no banco principal"
	@echo "make testes       - recria o banco s2id_teste e roda todos os testes"
	@echo "make dicionario   - regenera docs/05-dicionario-de-dados.md"
	@echo "make benchmark    - mede índices com volume sintético (desfaz tudo ao final)"
	@echo "make ibge         - baixa e carrega território real do IBGE"
	@echo "make atlas-perfil ARQUIVO=data/raw/atlas/xxx.xlsx - perfila o arquivo do Atlas"
	@echo "make atlas ARQUIVO=data/raw/atlas/xxx.xlsx        - carrega o arquivo do Atlas"
	@echo "make parar        - para os contêineres (mantém os dados)"

subir:
	docker compose up -d db
	docker compose run --rm migracoes

amostra:
	./scripts/carregar_amostra.sh

testes:
	./scripts/rodar_testes.sh

dicionario:
	python3 -m etl.gerar_dicionario

benchmark:
	PGDATABASE=s2id_teste psql -X -f scripts/benchmark.sql

ibge:
	./scripts/baixar_fontes_ibge.sh
	python3 -m etl.carregar_ibge --municipios data/raw/ibge/municipios.json \
	    --malha-uf data/raw/ibge/malha_ufs.json --malha-mun data/raw/ibge/malha_municipios.json

atlas-perfil:
	python3 -m etl.carregar_atlas --arquivo $(ARQUIVO) --perfil

atlas:
	python3 -m etl.carregar_atlas --arquivo $(ARQUIVO)

parar:
	docker compose stop
