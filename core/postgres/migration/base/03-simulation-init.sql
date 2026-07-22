\connect simulation;

CREATE SCHEMA IF NOT EXISTS public AUTHORIZATION postgres;

CREATE OR REPLACE FUNCTION public.trs_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$function$
;

CREATE SEQUENCE public.trs_faker_semantic_data_types_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_mapping_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_simulation_run_results_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_simulation_runs_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_simulation_suites_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_context_field_strategies_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_context_generated_messages_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_context_sim_pairs_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_context_txtp_configs_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_enrichment_field_strategies_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_enrichment_generated_rows_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_enrichment_tables_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_generations_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_trigger_field_overrides_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_trigger_generated_messages_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE SEQUENCE public.trs_suite_trigger_txtp_configs_id_seq
	INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE;

CREATE TABLE public.trs_faker_semantic_data_types (
	id bigserial NOT NULL,
	"name" varchar(255) NOT NULL,
	CONSTRAINT trs_faker_semantic_data_types_pkey PRIMARY KEY (id)
);

CREATE TABLE public.trs_mapping (
	id bigserial NOT NULL,
	primary_tx_id int8 NOT NULL,
	related_tx_id int8 NOT NULL,
	"mapping" jsonb DEFAULT '[]'::jsonb NOT NULL,
	CONSTRAINT trs_mapping_pkey PRIMARY KEY (id)
);

CREATE TABLE public.trs_simulation_suites (
	id bigserial NOT NULL,
	tenant_id varchar(255) NOT NULL,
	"name" varchar(120) NOT NULL,
	description varchar(500) NULL,
	simulation_type varchar(30) DEFAULT 'SINGLE_RULE'::character varying NOT NULL,
	status varchar(32) DEFAULT 'DRAFT'::character varying NOT NULL,
	rule_repo varchar(255) NULL,
	rule_name varchar(255) NULL,
	rule_version varchar(128) NULL,
	primary_txtp varchar(80) NULL,
	primary_txtp_version varchar(80) NULL,
	clone_source_suite_id int8 NULL,
	iteration_count int4 DEFAULT 0 NOT NULL,
	run_count int4 DEFAULT 0 NOT NULL,
	last_run_at timestamptz NULL,
	wizard_progress jsonb DEFAULT '{}'::jsonb NOT NULL,
	metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
	created_by varchar(255) NOT NULL,
	created_by_email varchar(255) NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	rule_config jsonb DEFAULT '{}'::jsonb NOT NULL,
	CONSTRAINT chk_trs_simulation_suites_simulation_type CHECK (((simulation_type)::text = ANY ((ARRAY['SINGLE_RULE'::character varying, 'INTEGRATION_TESTING'::character varying])::text[]))),
	CONSTRAINT chk_trs_simulation_suites_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'RUNNING'::character varying, 'COMPLETED'::character varying, 'FAILED'::character varying, 'ARCHIVED'::character varying])::text[]))),
	CONSTRAINT trs_simulation_suites_pkey PRIMARY KEY (id),
	CONSTRAINT trs_simulation_suites_clone_source_suite_id_fkey FOREIGN KEY (clone_source_suite_id) REFERENCES public.trs_simulation_suites(id)
);
CREATE INDEX idx_sim_suites_primary_txtp ON public.trs_simulation_suites USING btree (primary_txtp);
CREATE INDEX idx_sim_suites_rule ON public.trs_simulation_suites USING btree (rule_name);
CREATE INDEX idx_sim_suites_status ON public.trs_simulation_suites USING btree (status);
CREATE INDEX idx_sim_suites_tenant ON public.trs_simulation_suites USING btree (tenant_id);
CREATE INDEX idx_sim_suites_tenant_name ON public.trs_simulation_suites USING btree (tenant_id, name);
CREATE INDEX idx_sim_suites_tenant_status_updated ON public.trs_simulation_suites USING btree (tenant_id, status, updated_at DESC);
CREATE INDEX idx_sim_suites_updated ON public.trs_simulation_suites USING btree (updated_at DESC);

CREATE TRIGGER trg_trs_simulation_suites_updated_at BEFORE UPDATE ON
    public.trs_simulation_suites FOR EACH ROW EXECUTE FUNCTION trs_set_updated_at();

CREATE TABLE public.trs_suite_generations (
	id bigserial NOT NULL,
	suite_id int8 NOT NULL,
	generation_number int4 NOT NULL,
	status varchar(32) DEFAULT 'DRAFT'::character varying NOT NULL,
	simulation_type varchar(30) DEFAULT 'SINGLE_RULE'::character varying NOT NULL,
	rule_name varchar(255) NULL,
	rule_version varchar(128) NULL,
	context_count int4 DEFAULT 0 NOT NULL,
	trigger_count int4 DEFAULT 0 NOT NULL,
	enrichment_table_count int4 DEFAULT 0 NOT NULL,
	generated_context_count int4 DEFAULT 0 NOT NULL,
	generated_trigger_count int4 DEFAULT 0 NOT NULL,
	generated_enrichment_row_count int4 DEFAULT 0 NOT NULL,
	context_field_config_count int4 DEFAULT 0 NOT NULL,
	trigger_field_config_count int4 DEFAULT 0 NOT NULL,
	enrichment_field_config_count int4 DEFAULT 0 NOT NULL,
	wizard_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
	generation_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
	created_by varchar(255) NOT NULL,
	created_by_email varchar(255) NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	faker_seed int8 NULL,
	CONSTRAINT chk_trs_suite_generations_simulation_type CHECK (((simulation_type)::text = ANY ((ARRAY['SINGLE_RULE'::character varying, 'INTEGRATION_TESTING'::character varying])::text[]))),
	CONSTRAINT chk_trs_suite_generations_status CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'READY'::character varying, 'RUNNING'::character varying, 'COMPLETED'::character varying, 'FAILED'::character varying, 'ARCHIVED'::character varying])::text[]))),
	CONSTRAINT trs_suite_generations_pkey PRIMARY KEY (id),
	CONSTRAINT uq_trs_suite_generations_suite_generation UNIQUE (suite_id, generation_number),
	CONSTRAINT trs_suite_generations_suite_id_fkey FOREIGN KEY (suite_id) REFERENCES public.trs_simulation_suites(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_generations_created_at ON public.trs_suite_generations USING btree (created_at DESC);
CREATE INDEX idx_trs_suite_generations_suite_id ON public.trs_suite_generations USING btree (suite_id);

CREATE TRIGGER trg_trs_suite_generations_updated_at BEFORE UPDATE ON
    public.trs_suite_generations FOR EACH ROW EXECUTE FUNCTION trs_set_updated_at();

CREATE TABLE public.trs_simulation_runs (
	id bigserial NOT NULL,
	suite_id int8 NOT NULL,
	generation_id int8 NOT NULL,
	rule_name varchar(255) NOT NULL,
	rule_version varchar(255) NOT NULL,
	outcome varchar(255) NOT NULL,
	trigger_count int4 NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	updated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT trs_simulation_runs_pkey PRIMARY KEY (id),
	CONSTRAINT uq_trs_simulation_runs UNIQUE (suite_id, generation_id)
);
CREATE INDEX idx_trs_simulation_runs_created_at ON public.trs_simulation_runs USING btree (created_at DESC);
CREATE INDEX idx_trs_simulation_runs_suite_generation ON public.trs_simulation_runs USING btree (suite_id, generation_id);

CREATE TRIGGER trg_trs_simulation_runs_updated_at BEFORE UPDATE ON
    public.trs_simulation_runs FOR EACH ROW EXECUTE FUNCTION trs_set_updated_at();

CREATE TABLE public.trs_simulation_run_results (
	id bigserial NOT NULL,
	run_id int8 NOT NULL,
	outcome varchar(80) NULL,
	independent_variable numeric NULL,
	sub_rule_ref varchar(16) NOT NULL,
	rule_result jsonb NULL,
	received_at timestamptz DEFAULT now() NOT NULL,
	trigger_id int8 NULL,
	CONSTRAINT trs_simulation_run_results_pkey PRIMARY KEY (id)
);
CREATE INDEX idx_trs_simulation_run_results_band ON public.trs_simulation_run_results USING btree (sub_rule_ref);
CREATE INDEX idx_trs_simulation_run_results_run_id ON public.trs_simulation_run_results USING btree (run_id);

CREATE TABLE public.trs_suite_trigger_txtp_configs (
	id bigserial NOT NULL,
	generation_id int8 NOT NULL,
	txtp varchar(80) NOT NULL,
	txtp_version varchar(80) NOT NULL,
	display_order int4 NOT NULL,
	message_count int4 NOT NULL,
	link_to_context_pairs bool DEFAULT false NOT NULL,
	payload_template_json jsonb NOT NULL,
	expected_independent_variable numeric NULL,
	expected_result_band varchar(16) NULL,
	notes text NULL,
	faker_seed int8 NULL,
	generator_profile jsonb DEFAULT '{}'::jsonb NOT NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	related_txtp_config_id int4 NULL,
	related_transaction text NULL,
	CONSTRAINT chk_trs_suite_trigger_txtp_configs_expected_band CHECK (((expected_result_band IS NULL) OR ((expected_result_band)::text = ANY ((ARRAY['good'::character varying, 'neutral'::character varying, 'bad'::character varying, 'error'::character varying])::text[])))),
	CONSTRAINT trs_suite_trigger_txtp_configs_message_count_check CHECK ((message_count >= 1)),
	CONSTRAINT trs_suite_trigger_txtp_configs_pkey PRIMARY KEY (id),
	CONSTRAINT uq_trs_suite_trigger_txtp_configs UNIQUE (generation_id, txtp, txtp_version, display_order),
	CONSTRAINT trs_suite_trigger_txtp_configs_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES public.trs_suite_generations(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_trigger_txtp_configs_generation_id ON public.trs_suite_trigger_txtp_configs USING btree (generation_id);

CREATE TABLE public.trs_suite_context_txtp_configs (
	id bigserial NOT NULL,
	generation_id int8 NOT NULL,
	txtp varchar(80) NOT NULL,
	txtp_version varchar(80) NOT NULL,
	display_order int4 NOT NULL,
	message_count int4 NOT NULL,
	schema_snapshot jsonb NOT NULL,
	sample_payload_snapshot jsonb NULL,
	faker_seed int8 NULL,
	generator_profile jsonb DEFAULT '{}'::jsonb NOT NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	related_txtp_config_id int4 NULL,
	related_transaction text NULL,
	CONSTRAINT trs_suite_context_txtp_configs_message_count_check CHECK ((message_count >= 1)),
	CONSTRAINT trs_suite_context_txtp_configs_pkey PRIMARY KEY (id),
	CONSTRAINT uq_trs_suite_context_txtp_configs UNIQUE (generation_id, txtp, txtp_version, display_order),
	CONSTRAINT trs_suite_context_txtp_configs_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES public.trs_suite_generations(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_context_txtp_configs_generation_id ON public.trs_suite_context_txtp_configs USING btree (generation_id);

CREATE TABLE public.trs_suite_enrichment_tables (
	id bigserial NOT NULL,
	generation_id int8 NOT NULL,
	table_name varchar(63) NOT NULL,
	table_order int4 DEFAULT 1 NOT NULL,
	row_count int4 DEFAULT 0 NOT NULL,
	payload_template_json jsonb NULL,
	schema_template_json jsonb NULL,
	faker_profile jsonb DEFAULT '{}'::jsonb NOT NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT trs_suite_enrichment_tables_pkey PRIMARY KEY (id),
	CONSTRAINT trs_suite_enrichment_tables_row_count_check CHECK ((row_count >= 0)),
	CONSTRAINT uq_trs_suite_enrichment_tables UNIQUE (generation_id, table_name),
	CONSTRAINT trs_suite_enrichment_tables_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES public.trs_suite_generations(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_enrichment_tables_generation_id ON public.trs_suite_enrichment_tables USING btree (generation_id);

CREATE TABLE public.trs_suite_trigger_field_strategies (
	id int8 DEFAULT nextval('trs_suite_trigger_field_overrides_id_seq'::regclass) NOT NULL,
	trigger_txtp_config_id int8 NOT NULL,
	field_path text NOT NULL,
	strategy_code varchar(24) NOT NULL,
	static_value jsonb NULL,
	range_min numeric NULL,
	range_max numeric NULL,
	faker_semantic_type varchar(64) NULL,
	generator_options jsonb DEFAULT '{}'::jsonb NOT NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT chk_trs_suite_trigger_field_overrides_range CHECK ((((strategy_code)::text <> 'range'::text) OR ((range_min IS NOT NULL) AND (range_max IS NOT NULL) AND (range_min <= range_max)))),
	CONSTRAINT chk_trs_suite_trigger_field_strategy_code CHECK (((strategy_code)::text = ANY ((ARRAY['keep_sample'::character varying, 'static'::character varying, 'range'::character varying, 'skip'::character varying, 'random'::character varying])::text[]))),
	CONSTRAINT trs_suite_trigger_field_overrides_pkey PRIMARY KEY (id),
	CONSTRAINT uq_trs_suite_trigger_field_overrides UNIQUE (trigger_txtp_config_id, field_path),
	CONSTRAINT trs_suite_trigger_field_overrides_trigger_txtp_config_id_fkey FOREIGN KEY (trigger_txtp_config_id) REFERENCES public.trs_suite_trigger_txtp_configs(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_trigger_field_overrides_config_id ON public.trs_suite_trigger_field_strategies USING btree (trigger_txtp_config_id);

CREATE TABLE public.trs_suite_context_field_strategies (
	id bigserial NOT NULL,
	context_txtp_config_id int8 NOT NULL,
	field_path text NOT NULL,
	strategy_code varchar(24) NOT NULL,
	static_value jsonb NULL,
	range_min numeric NULL,
	range_max numeric NULL,
	faker_semantic_type varchar(64) NULL,
	generator_options jsonb DEFAULT '{}'::jsonb NOT NULL,
	is_required_override bool NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT chk_trs_suite_context_field_strategies_range CHECK ((((strategy_code)::text <> 'range'::text) OR ((range_min IS NOT NULL) AND (range_max IS NOT NULL) AND (range_min <= range_max)))),
	CONSTRAINT chk_trs_suite_context_field_strategies_strategy CHECK (((strategy_code)::text = ANY ((ARRAY['keep_sample'::character varying, 'static'::character varying, 'range'::character varying, 'skip'::character varying, 'random'::character varying])::text[]))),
	CONSTRAINT trs_suite_context_field_strategies_pkey PRIMARY KEY (id),
	CONSTRAINT uq_trs_suite_context_field_strategies UNIQUE (context_txtp_config_id, field_path),
	CONSTRAINT trs_suite_context_field_strategies_context_txtp_config_id_fkey FOREIGN KEY (context_txtp_config_id) REFERENCES public.trs_suite_context_txtp_configs(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_context_field_strategies_config_id ON public.trs_suite_context_field_strategies USING btree (context_txtp_config_id);

CREATE TABLE public.trs_suite_context_generated_messages (
	id bigserial NOT NULL,
	context_txtp_config_id int8 NOT NULL,
	message_order int4 NOT NULL,
	payload_json jsonb NOT NULL,
	payload_hash bpchar(64) NULL,
	validation_status varchar(16) DEFAULT 'VALID'::character varying NOT NULL,
	validation_errors jsonb NULL,
	generated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT trs_suite_context_generated_messages_message_order_check CHECK ((message_order >= 1)),
	CONSTRAINT trs_suite_context_generated_messages_pkey PRIMARY KEY (id),
	CONSTRAINT trs_suite_context_generated_messages_validation_status_check CHECK (((validation_status)::text = ANY ((ARRAY['VALID'::character varying, 'INVALID'::character varying])::text[]))),
	CONSTRAINT uq_trs_suite_context_generated_messages UNIQUE (context_txtp_config_id, message_order),
	CONSTRAINT trs_suite_context_generated_message_context_txtp_config_id_fkey FOREIGN KEY (context_txtp_config_id) REFERENCES public.trs_suite_context_txtp_configs(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_context_generated_messages_config_id ON public.trs_suite_context_generated_messages USING btree (context_txtp_config_id);
CREATE INDEX idx_trs_suite_context_generated_messages_generated_at ON public.trs_suite_context_generated_messages USING btree (generated_at DESC);

CREATE TABLE public.trs_suite_enrichment_field_strategies (
	id bigserial NOT NULL,
	enrichment_table_id int8 NOT NULL,
	column_name varchar(128) NOT NULL,
	column_type varchar(64) NULL,
	strategy_code varchar(24) NOT NULL,
	static_value jsonb NULL,
	range_min numeric NULL,
	range_max numeric NULL,
	generator_type varchar(64) NULL,
	generator_options jsonb DEFAULT '{}'::jsonb NOT NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT chk_trs_suite_enrichment_field_strategies_range CHECK ((((strategy_code)::text <> 'range'::text) OR ((range_min IS NOT NULL) AND (range_max IS NOT NULL) AND (range_min <= range_max)))),
	CONSTRAINT chk_trs_suite_enrichment_field_strategies_strategy CHECK (((strategy_code)::text = ANY ((ARRAY['keep_sample'::character varying, 'static'::character varying, 'range'::character varying, 'skip'::character varying, 'random'::character varying])::text[]))),
	CONSTRAINT trs_suite_enrichment_field_strategies_pkey PRIMARY KEY (id),
	CONSTRAINT uq_trs_suite_enrichment_field_strategies UNIQUE (enrichment_table_id, column_name),
	CONSTRAINT trs_suite_enrichment_field_strategies_enrichment_table_id_fkey FOREIGN KEY (enrichment_table_id) REFERENCES public.trs_suite_enrichment_tables(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_enrichment_field_strategies_table_id ON public.trs_suite_enrichment_field_strategies USING btree (enrichment_table_id);

CREATE TABLE public.trs_suite_enrichment_generated_rows (
	id bigserial NOT NULL,
	enrichment_table_id int8 NOT NULL,
	row_order int4 NOT NULL,
	record_json jsonb NOT NULL,
	generated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT trs_suite_enrichment_generated_rows_pkey PRIMARY KEY (id),
	CONSTRAINT trs_suite_enrichment_generated_rows_row_order_check CHECK ((row_order >= 1)),
	CONSTRAINT uq_trs_suite_enrichment_generated_rows UNIQUE (enrichment_table_id, row_order),
	CONSTRAINT trs_suite_enrichment_generated_rows_enrichment_table_id_fkey FOREIGN KEY (enrichment_table_id) REFERENCES public.trs_suite_enrichment_tables(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_enrichment_generated_rows_table_id ON public.trs_suite_enrichment_generated_rows USING btree (enrichment_table_id);

CREATE TABLE public.trs_suite_trigger_generated_messages (
	id bigserial NOT NULL,
	trigger_txtp_config_id int8 NOT NULL,
	message_order int4 NOT NULL,
	payload_json jsonb NOT NULL,
	end_to_end_id varchar(140) NULL,
	linked_context_message_id int8 NULL,
	validation_status varchar(16) DEFAULT 'VALID'::character varying NOT NULL,
	validation_errors jsonb NULL,
	generated_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT trs_suite_trigger_generated_messages_message_order_check CHECK ((message_order >= 1)),
	CONSTRAINT trs_suite_trigger_generated_messages_pkey PRIMARY KEY (id),
	CONSTRAINT trs_suite_trigger_generated_messages_validation_status_check CHECK (((validation_status)::text = ANY ((ARRAY['VALID'::character varying, 'INVALID'::character varying])::text[]))),
	CONSTRAINT uq_trs_suite_trigger_generated_messages UNIQUE (trigger_txtp_config_id, message_order),
	CONSTRAINT trs_suite_trigger_generated_mess_linked_context_message_id_fkey FOREIGN KEY (linked_context_message_id) REFERENCES public.trs_suite_context_generated_messages(id),
	CONSTRAINT trs_suite_trigger_generated_message_trigger_txtp_config_id_fkey FOREIGN KEY (trigger_txtp_config_id) REFERENCES public.trs_suite_trigger_txtp_configs(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_trigger_generated_messages_config_id ON public.trs_suite_trigger_generated_messages USING btree (trigger_txtp_config_id);
CREATE INDEX idx_trs_suite_trigger_generated_messages_e2e ON public.trs_suite_trigger_generated_messages USING btree (end_to_end_id);

CREATE TABLE public.trs_simulation_run_result_context_links (
	run_result_id int8 NOT NULL,
	context_message_id int8 NOT NULL,
	CONSTRAINT trs_simulation_run_result_context_links_pkey PRIMARY KEY (run_result_id, context_message_id),
	CONSTRAINT trs_simulation_run_result_context_links_context_message_id_fkey FOREIGN KEY (context_message_id) REFERENCES public.trs_suite_context_generated_messages(id) ON DELETE CASCADE,
	CONSTRAINT trs_simulation_run_result_context_links_run_result_id_fkey FOREIGN KEY (run_result_id) REFERENCES public.trs_simulation_run_results(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_simulation_run_result_context_links_context ON public.trs_simulation_run_result_context_links USING btree (context_message_id);

CREATE TABLE public.trs_suite_context_sim_pairs (
	id bigserial NOT NULL,
	generation_id int8 NOT NULL,
	pair_order int4 NOT NULL,
	context_message_id int8 NOT NULL,
	trigger_message_id int8 NOT NULL,
	context_payload_json jsonb NULL,
	trigger_payload_json jsonb NULL,
	validation_status varchar(16) DEFAULT 'VALID'::character varying NOT NULL,
	pairing_key varchar(140) NULL,
	created_at timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT trs_suite_context_sim_pairs_pair_order_check CHECK ((pair_order >= 1)),
	CONSTRAINT trs_suite_context_sim_pairs_pkey PRIMARY KEY (id),
	CONSTRAINT trs_suite_context_sim_pairs_validation_status_check CHECK (((validation_status)::text = ANY ((ARRAY['VALID'::character varying, 'INVALID'::character varying, 'SKIPPED'::character varying])::text[]))),
	CONSTRAINT uq_trs_suite_context_sim_pairs_message UNIQUE (context_message_id, trigger_message_id),
	CONSTRAINT uq_trs_suite_context_sim_pairs_order UNIQUE (generation_id, pair_order),
	CONSTRAINT trs_suite_context_sim_pairs_context_message_id_fkey FOREIGN KEY (context_message_id) REFERENCES public.trs_suite_context_generated_messages(id) ON DELETE CASCADE,
	CONSTRAINT trs_suite_context_sim_pairs_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES public.trs_suite_generations(id) ON DELETE CASCADE,
	CONSTRAINT trs_suite_context_sim_pairs_trigger_message_id_fkey FOREIGN KEY (trigger_message_id) REFERENCES public.trs_suite_trigger_generated_messages(id) ON DELETE CASCADE
);
CREATE INDEX idx_trs_suite_context_sim_pairs_generation_id ON public.trs_suite_context_sim_pairs USING btree (generation_id);
