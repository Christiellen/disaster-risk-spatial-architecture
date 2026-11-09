-- =====================================================================
-- V5 - Ocorrência de desastre e danos
-- Uma ocorrência = um registro de desastre em um município, classificado
-- por um código COBRADE folha, em uma data de evento.
-- =====================================================================

CREATE TABLE core.ocorrencia (
    id_ocorrencia   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    chave_origem    text        NOT NULL UNIQUE,
    protocolo       text,
    cd_mun          char(7)     NOT NULL REFERENCES core.municipio (cd_mun),
    cd_cobrade      char(5)     NOT NULL,
    cobrade_classificavel boolean NOT NULL DEFAULT true CHECK (cobrade_classificavel),
    dt_evento       date        NOT NULL CHECK (dt_evento >= DATE '1900-01-01'),
    dt_registro     date,
    situacao        text,
    id_lote_origem  bigint      NOT NULL REFERENCES controle.lote_carga (id_lote),
    linha_origem    integer     NOT NULL CHECK (linha_origem > 0),
    versao          integer     NOT NULL DEFAULT 1 CHECK (versao >= 1),
    criado_em       timestamptz NOT NULL DEFAULT now(),
    atualizado_em   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT fk_ocorrencia_cobrade_folha
        FOREIGN KEY (cd_cobrade, cobrade_classificavel)
        REFERENCES core.cobrade (cd_cobrade, classificavel),
    CONSTRAINT ck_ocorrencia_registro_apos_evento
        CHECK (dt_registro IS NULL OR dt_registro >= dt_evento),
    CONSTRAINT ck_ocorrencia_protocolo_formato
        CHECK (protocolo IS NULL OR protocolo ~ '^[A-Z0-9][A-Z0-9./-]{3,}$'),
    CONSTRAINT ck_ocorrencia_atualizacao
        CHECK (atualizado_em >= criado_em)
);

CREATE UNIQUE INDEX uq_ocorrencia_protocolo ON core.ocorrencia (protocolo) WHERE protocolo IS NOT NULL;
CREATE INDEX ix_ocorrencia_cobrade_data ON core.ocorrencia (cd_cobrade, dt_evento);
CREATE INDEX ix_ocorrencia_mun_data     ON core.ocorrencia (cd_mun, dt_evento);
CREATE INDEX ix_ocorrencia_atualizado   ON core.ocorrencia (atualizado_em);
CREATE INDEX ix_ocorrencia_lote         ON core.ocorrencia (id_lote_origem);

COMMENT ON TABLE  core.ocorrencia IS 'Registro de desastre em um município. Unidade central do modelo.';
COMMENT ON COLUMN core.ocorrencia.id_ocorrencia IS 'Chave substituta interna. Nunca exposta como identificador de negócio.';
COMMENT ON COLUMN core.ocorrencia.chave_origem IS 'Chave natural estável: protocolo do S2iD quando existe; senão, hash determinístico de município + COBRADE + data do evento (ver ADR-0006).';
COMMENT ON COLUMN core.ocorrencia.protocolo IS 'Protocolo do registro no S2iD, quando informado pela fonte.';
COMMENT ON COLUMN core.ocorrencia.cd_mun IS 'Município afetado.';
COMMENT ON COLUMN core.ocorrencia.cd_cobrade IS 'Tipologia COBRADE. Só aceita nós-folha (FK composta com classificavel).';
COMMENT ON COLUMN core.ocorrencia.cobrade_classificavel IS 'Coluna técnica fixa em verdadeiro; viabiliza a FK composta que restringe a classificação a nós-folha.';
COMMENT ON COLUMN core.ocorrencia.dt_evento IS 'Data de início do evento adverso.';
COMMENT ON COLUMN core.ocorrencia.dt_registro IS 'Data de registro no sistema. Não pode ser anterior ao evento.';
COMMENT ON COLUMN core.ocorrencia.situacao IS 'Situação informada pela fonte. Domínio ainda aberto até o perfilamento completo (pendência P-02).';
COMMENT ON COLUMN core.ocorrencia.id_lote_origem IS 'Lote que criou ou atualizou por último o registro.';
COMMENT ON COLUMN core.ocorrencia.linha_origem IS 'Linha do arquivo de origem no lote indicado.';
COMMENT ON COLUMN core.ocorrencia.versao IS 'Versão do registro. Incrementada a cada alteração; usada em controle otimista de concorrência (ADR-0007).';
COMMENT ON COLUMN core.ocorrencia.criado_em IS 'Momento da criação.';
COMMENT ON COLUMN core.ocorrencia.atualizado_em IS 'Momento da última alteração. Base da sincronização incremental.';

CREATE TABLE core.ocorrencia_dano (
    id_ocorrencia bigint        NOT NULL REFERENCES core.ocorrencia (id_ocorrencia) ON DELETE CASCADE,
    cd_indicador  text          NOT NULL REFERENCES core.indicador_dano (cd_indicador),
    valor         numeric(18,2) NOT NULL CHECK (valor >= 0),
    PRIMARY KEY (id_ocorrencia, cd_indicador)
);

CREATE INDEX ix_dano_indicador ON core.ocorrencia_dano (cd_indicador);

COMMENT ON TABLE  core.ocorrencia_dano IS 'Valor de cada indicador de dano por ocorrência (modelo longo). Ausência de linha = não informado; zero = informado como zero.';
COMMENT ON COLUMN core.ocorrencia_dano.id_ocorrencia IS 'Ocorrência.';
COMMENT ON COLUMN core.ocorrencia_dano.cd_indicador IS 'Indicador de dano.';
COMMENT ON COLUMN core.ocorrencia_dano.valor IS 'Valor não negativo, na unidade definida em core.indicador_dano.';

-- Pessoas e valores devem ser inteiros quando a unidade não é monetária.
CREATE FUNCTION core.fn_valida_unidade_dano() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_unidade text;
BEGIN
    SELECT unidade INTO v_unidade FROM core.indicador_dano WHERE cd_indicador = NEW.cd_indicador;
    IF v_unidade IN ('PESSOAS', 'UNIDADES') AND NEW.valor <> trunc(NEW.valor) THEN
        RAISE EXCEPTION 'Indicador % (unidade %) exige valor inteiro; recebido %', NEW.cd_indicador, v_unidade, NEW.valor
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION core.fn_valida_unidade_dano() IS 'Garante valores inteiros para indicadores contados em pessoas ou unidades.';

CREATE TRIGGER tg_dano_unidade
    BEFORE INSERT OR UPDATE ON core.ocorrencia_dano
    FOR EACH ROW EXECUTE FUNCTION core.fn_valida_unidade_dano();
