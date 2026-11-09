-- =====================================================================
-- V12 - Papéis e permissões (menor privilégio)
-- Papéis sem login: contas reais recebem o papel por GRANT.
--   s2id_consumidor : leitura apenas do contrato (schema api)
--   s2id_analista   : leitura do core e do analítico
--   s2id_carga      : escrita em staging/controle e execução das cargas
-- =====================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 's2id_consumidor') THEN CREATE ROLE s2id_consumidor NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 's2id_analista')   THEN CREATE ROLE s2id_analista   NOLOGIN; END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 's2id_carga')      THEN CREATE ROLE s2id_carga      NOLOGIN; END IF;
END;
$$;

REVOKE ALL ON SCHEMA staging, controle, core, hist, risco, api, analitico FROM PUBLIC;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA staging, controle, core, hist, risco, api, analitico FROM PUBLIC;

-- Consumidor: só o contrato
GRANT USAGE ON SCHEMA api TO s2id_consumidor;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO s2id_consumidor;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO s2id_consumidor;

-- Analista: leitura ampla, nenhuma escrita
GRANT USAGE ON SCHEMA core, risco, analitico, api, controle TO s2id_analista;
GRANT SELECT ON ALL TABLES IN SCHEMA core, risco, analitico, api, controle TO s2id_analista;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO s2id_analista;

-- Carga: staging e controle; promoção ao core apenas via funções de carga
GRANT USAGE ON SCHEMA staging, controle, core, risco, analitico TO s2id_carga;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA staging, controle TO s2id_carga;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA core, risco TO s2id_carga;
GRANT DELETE ON core.ocorrencia_dano TO s2id_carga;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA controle, core, risco TO s2id_carga;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA staging, core, risco, analitico TO s2id_carga;
