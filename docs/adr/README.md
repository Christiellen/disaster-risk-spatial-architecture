# Registro de decisões arquiteturais (ADR)

Cada decisão relevante tem um registro curto com contexto, alternativas avaliadas, decisão e consequências. Decisões não são apagadas: quando mudam, um novo ADR substitui o anterior e o antigo é marcado como "Substituído".

| ADR | Decisão | Situação |
|---|---|---|
| [0001](0001-registrar-decisoes.md) | Registrar decisões arquiteturais em ADRs no repositório | Aceito |
| [0002](0002-camadas-por-schema.md) | Separar staging, controle, core, hist, risco, api e analitico em schemas | Aceito |
| [0003](0003-srid-sirgas-2000.md) | SIRGAS 2000 (EPSG 4674) para armazenamento; geography para distâncias | Aceito |
| [0004](0004-cobrade-arvore.md) | COBRADE como árvore autorreferenciada; só folhas classificam | Aceito |
| [0005](0005-danos-modelo-longo.md) | Danos em modelo longo com catálogo de indicadores | Aceito |
| [0006](0006-chaves.md) | Chave natural (protocolo ou hash) + chave substituta interna | Aceito |
| [0007](0007-historico-e-versao.md) | Changelog por gatilho e concorrência otimista por versão | Aceito |
| [0008](0008-contrato-api.md) | Contrato de integração versionado no schema api | Aceito |
| [0009](0009-banco-como-codigo.md) | Migrações versionadas, testes no banco e dicionário gerado do catálogo | Aceito |
