-- =====================================================================
-- V1 - Schemas e extensões
-- Separação por responsabilidade (ver ADR-0002):
--   staging   : dados brutos, como chegaram da fonte (tudo texto)
--   controle  : rastreabilidade de cargas (lotes, rejeições)
--   core      : modelo normalizado e íntegro (fonte da verdade)
--   hist      : histórico de alterações (auditoria e "as-of")
--   risco     : camadas geoespaciais de risco
--   api       : contrato estável para consumidores externos
--   analitico : visões materializadas para consulta e BI
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- digest() para hash de chaves de origem

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS controle;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS hist;
CREATE SCHEMA IF NOT EXISTS risco;
CREATE SCHEMA IF NOT EXISTS api;
CREATE SCHEMA IF NOT EXISTS analitico;

COMMENT ON SCHEMA staging   IS 'Dados brutos recebidos das fontes, sem tipagem nem regras. Nunca consumidos diretamente.';
COMMENT ON SCHEMA controle  IS 'Rastreabilidade das cargas: lotes, hashes de arquivo e registros rejeitados com motivo.';
COMMENT ON SCHEMA core      IS 'Modelo normalizado de território, classificação COBRADE, ocorrências e danos. Fonte da verdade.';
COMMENT ON SCHEMA hist      IS 'Histórico de alterações das tabelas do core, alimentado por gatilhos.';
COMMENT ON SCHEMA risco     IS 'Camadas geoespaciais de áreas de risco (ex.: setorização do SGB).';
COMMENT ON SCHEMA api       IS 'Contrato de integração versionado (v1). Único schema exposto a consumidores externos.';
COMMENT ON SCHEMA analitico IS 'Visões materializadas para consultas analíticas e painéis.';
