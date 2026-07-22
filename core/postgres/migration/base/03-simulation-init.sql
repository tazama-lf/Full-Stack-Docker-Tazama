\connect simulation;

--
-- PostgreSQL database dump
--


-- Dumped from database version 18.4 (Debian 18.4-1.pgdg13+1)
-- Dumped by pg_dump version 18.4 (Debian 18.4-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: trs_set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trs_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: trs_faker_semantic_data_types; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_faker_semantic_data_types (
    id bigint NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: trs_faker_semantic_data_types_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_faker_semantic_data_types_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_faker_semantic_data_types_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_faker_semantic_data_types_id_seq OWNED BY public.trs_faker_semantic_data_types.id;


--
-- Name: trs_mapping; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_mapping (
    id bigint NOT NULL,
    primary_tx_id bigint NOT NULL,
    related_tx_id bigint NOT NULL,
    mapping jsonb DEFAULT '[]'::jsonb NOT NULL
);


--
-- Name: trs_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_mapping_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_mapping_id_seq OWNED BY public.trs_mapping.id;


--
-- Name: trs_simulation_run_result_context_links; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_simulation_run_result_context_links (
    run_result_id bigint NOT NULL,
    context_message_id bigint CONSTRAINT trs_simulation_run_result_context_l_context_message_id_not_null NOT NULL
);


--
-- Name: trs_simulation_run_results; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_simulation_run_results (
    id bigint NOT NULL,
    run_id bigint NOT NULL,
    outcome character varying(80),
    independent_variable numeric,
    sub_rule_ref character varying(16) CONSTRAINT trs_simulation_run_results_result_band_not_null NOT NULL,
    rule_result jsonb,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    trigger_id bigint
);


--
-- Name: trs_simulation_run_results_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_simulation_run_results_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_simulation_run_results_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_simulation_run_results_id_seq OWNED BY public.trs_simulation_run_results.id;


--
-- Name: trs_simulation_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_simulation_runs (
    id bigint NOT NULL,
    suite_id bigint NOT NULL,
    generation_id bigint NOT NULL,
    rule_name character varying(255) NOT NULL,
    rule_version character varying(255) NOT NULL,
    outcome character varying(255) NOT NULL,
    trigger_count integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: trs_simulation_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_simulation_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_simulation_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_simulation_runs_id_seq OWNED BY public.trs_simulation_runs.id;


--
-- Name: trs_simulation_suites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_simulation_suites (
    id bigint NOT NULL,
    tenant_id character varying(255) NOT NULL,
    name character varying(120) NOT NULL,
    description character varying(500),
    simulation_type character varying(30) DEFAULT 'SINGLE_RULE'::character varying NOT NULL,
    status character varying(32) DEFAULT 'DRAFT'::character varying NOT NULL,
    rule_repo character varying(255),
    rule_name character varying(255),
    rule_version character varying(128),
    primary_txtp character varying(80),
    primary_txtp_version character varying(80),
    clone_source_suite_id bigint,
    iteration_count integer DEFAULT 0 NOT NULL,
    run_count integer DEFAULT 0 NOT NULL,
    last_run_at timestamp with time zone,
    wizard_progress jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by character varying(255) NOT NULL,
    created_by_email character varying(255),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    rule_config jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_trs_simulation_suites_simulation_type CHECK (((simulation_type)::text = ANY (ARRAY[('SINGLE_RULE'::character varying)::text, ('INTEGRATION_TESTING'::character varying)::text]))),
    CONSTRAINT chk_trs_simulation_suites_status CHECK (((status)::text = ANY (ARRAY[('DRAFT'::character varying)::text, ('RUNNING'::character varying)::text, ('COMPLETED'::character varying)::text, ('FAILED'::character varying)::text, ('ARCHIVED'::character varying)::text])))
);


--
-- Name: trs_simulation_suites_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_simulation_suites_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_simulation_suites_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_simulation_suites_id_seq OWNED BY public.trs_simulation_suites.id;


--
-- Name: trs_suite_context_field_strategies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_context_field_strategies (
    id bigint NOT NULL,
    context_txtp_config_id bigint CONSTRAINT trs_suite_context_field_strateg_context_txtp_config_id_not_null NOT NULL,
    field_path text NOT NULL,
    strategy_code character varying(24) NOT NULL,
    static_value jsonb,
    range_min numeric,
    range_max numeric,
    faker_semantic_type character varying(64),
    generator_options jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_required_override boolean,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_trs_suite_context_field_strategies_range CHECK ((((strategy_code)::text <> 'range'::text) OR ((range_min IS NOT NULL) AND (range_max IS NOT NULL) AND (range_min <= range_max)))),
    CONSTRAINT chk_trs_suite_context_field_strategies_strategy CHECK (((strategy_code)::text = ANY (ARRAY[('keep_sample'::character varying)::text, ('static'::character varying)::text, ('range'::character varying)::text, ('skip'::character varying)::text, ('random'::character varying)::text])))
);


--
-- Name: trs_suite_context_field_strategies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_context_field_strategies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_context_field_strategies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_context_field_strategies_id_seq OWNED BY public.trs_suite_context_field_strategies.id;


--
-- Name: trs_suite_context_generated_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_context_generated_messages (
    id bigint NOT NULL,
    context_txtp_config_id bigint CONSTRAINT trs_suite_context_generated_mes_context_txtp_config_id_not_null NOT NULL,
    message_order integer NOT NULL,
    payload_json jsonb NOT NULL,
    payload_hash character(64),
    validation_status character varying(16) DEFAULT 'VALID'::character varying NOT NULL,
    validation_errors jsonb,
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT trs_suite_context_generated_messages_message_order_check CHECK ((message_order >= 1)),
    CONSTRAINT trs_suite_context_generated_messages_validation_status_check CHECK (((validation_status)::text = ANY (ARRAY[('VALID'::character varying)::text, ('INVALID'::character varying)::text])))
);


--
-- Name: trs_suite_context_generated_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_context_generated_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_context_generated_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_context_generated_messages_id_seq OWNED BY public.trs_suite_context_generated_messages.id;


--
-- Name: trs_suite_context_sim_pairs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_context_sim_pairs (
    id bigint NOT NULL,
    generation_id bigint NOT NULL,
    pair_order integer NOT NULL,
    context_message_id bigint NOT NULL,
    trigger_message_id bigint NOT NULL,
    context_payload_json jsonb,
    trigger_payload_json jsonb,
    validation_status character varying(16) DEFAULT 'VALID'::character varying NOT NULL,
    pairing_key character varying(140),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT trs_suite_context_sim_pairs_pair_order_check CHECK ((pair_order >= 1)),
    CONSTRAINT trs_suite_context_sim_pairs_validation_status_check CHECK (((validation_status)::text = ANY (ARRAY[('VALID'::character varying)::text, ('INVALID'::character varying)::text, ('SKIPPED'::character varying)::text])))
);


--
-- Name: trs_suite_context_sim_pairs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_context_sim_pairs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_context_sim_pairs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_context_sim_pairs_id_seq OWNED BY public.trs_suite_context_sim_pairs.id;


--
-- Name: trs_suite_context_txtp_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_context_txtp_configs (
    id bigint NOT NULL,
    generation_id bigint NOT NULL,
    txtp character varying(80) NOT NULL,
    txtp_version character varying(80) NOT NULL,
    display_order integer NOT NULL,
    message_count integer NOT NULL,
    schema_snapshot jsonb NOT NULL,
    sample_payload_snapshot jsonb,
    faker_seed bigint,
    generator_profile jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    related_txtp_config_id integer,
    related_transaction text,
    CONSTRAINT trs_suite_context_txtp_configs_message_count_check CHECK ((message_count >= 1))
);


--
-- Name: trs_suite_context_txtp_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_context_txtp_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_context_txtp_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_context_txtp_configs_id_seq OWNED BY public.trs_suite_context_txtp_configs.id;


--
-- Name: trs_suite_enrichment_field_strategies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_enrichment_field_strategies (
    id bigint NOT NULL,
    enrichment_table_id bigint CONSTRAINT trs_suite_enrichment_field_strateg_enrichment_table_id_not_null NOT NULL,
    column_name character varying(128) NOT NULL,
    column_type character varying(64),
    strategy_code character varying(24) NOT NULL,
    static_value jsonb,
    range_min numeric,
    range_max numeric,
    generator_type character varying(64),
    generator_options jsonb DEFAULT '{}'::jsonb CONSTRAINT trs_suite_enrichment_field_strategie_generator_options_not_null NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_trs_suite_enrichment_field_strategies_range CHECK ((((strategy_code)::text <> 'range'::text) OR ((range_min IS NOT NULL) AND (range_max IS NOT NULL) AND (range_min <= range_max)))),
    CONSTRAINT chk_trs_suite_enrichment_field_strategies_strategy CHECK (((strategy_code)::text = ANY (ARRAY[('keep_sample'::character varying)::text, ('static'::character varying)::text, ('range'::character varying)::text, ('skip'::character varying)::text, ('random'::character varying)::text])))
);


--
-- Name: trs_suite_enrichment_field_strategies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_enrichment_field_strategies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_enrichment_field_strategies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_enrichment_field_strategies_id_seq OWNED BY public.trs_suite_enrichment_field_strategies.id;


--
-- Name: trs_suite_enrichment_generated_rows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_enrichment_generated_rows (
    id bigint NOT NULL,
    enrichment_table_id bigint CONSTRAINT trs_suite_enrichment_generated_row_enrichment_table_id_not_null NOT NULL,
    row_order integer NOT NULL,
    record_json jsonb NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT trs_suite_enrichment_generated_rows_row_order_check CHECK ((row_order >= 1))
);


--
-- Name: trs_suite_enrichment_generated_rows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_enrichment_generated_rows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_enrichment_generated_rows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_enrichment_generated_rows_id_seq OWNED BY public.trs_suite_enrichment_generated_rows.id;


--
-- Name: trs_suite_enrichment_tables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_enrichment_tables (
    id bigint NOT NULL,
    generation_id bigint NOT NULL,
    table_name character varying(63) NOT NULL,
    table_order integer DEFAULT 1 NOT NULL,
    row_count integer DEFAULT 0 NOT NULL,
    payload_template_json jsonb,
    schema_template_json jsonb,
    faker_profile jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT trs_suite_enrichment_tables_row_count_check CHECK ((row_count >= 0))
);


--
-- Name: trs_suite_enrichment_tables_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_enrichment_tables_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_enrichment_tables_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_enrichment_tables_id_seq OWNED BY public.trs_suite_enrichment_tables.id;


--
-- Name: trs_suite_generations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_generations (
    id bigint NOT NULL,
    suite_id bigint NOT NULL,
    generation_number integer NOT NULL,
    status character varying(32) DEFAULT 'DRAFT'::character varying NOT NULL,
    simulation_type character varying(30) DEFAULT 'SINGLE_RULE'::character varying NOT NULL,
    rule_name character varying(255),
    rule_version character varying(128),
    context_count integer DEFAULT 0 NOT NULL,
    trigger_count integer DEFAULT 0 NOT NULL,
    enrichment_table_count integer DEFAULT 0 NOT NULL,
    generated_context_count integer DEFAULT 0 NOT NULL,
    generated_trigger_count integer DEFAULT 0 NOT NULL,
    generated_enrichment_row_count integer DEFAULT 0 NOT NULL,
    context_field_config_count integer DEFAULT 0 NOT NULL,
    trigger_field_config_count integer DEFAULT 0 NOT NULL,
    enrichment_field_config_count integer DEFAULT 0 NOT NULL,
    wizard_snapshot jsonb DEFAULT '{}'::jsonb NOT NULL,
    generation_metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by character varying(255) NOT NULL,
    created_by_email character varying(255),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    faker_seed bigint,
    CONSTRAINT chk_trs_suite_generations_simulation_type CHECK (((simulation_type)::text = ANY (ARRAY[('SINGLE_RULE'::character varying)::text, ('INTEGRATION_TESTING'::character varying)::text]))),
    CONSTRAINT chk_trs_suite_generations_status CHECK (((status)::text = ANY (ARRAY[('DRAFT'::character varying)::text, ('READY'::character varying)::text, ('RUNNING'::character varying)::text, ('COMPLETED'::character varying)::text, ('FAILED'::character varying)::text, ('ARCHIVED'::character varying)::text])))
);


--
-- Name: trs_suite_generations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_generations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_generations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_generations_id_seq OWNED BY public.trs_suite_generations.id;


--
-- Name: trs_suite_trigger_field_strategies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_trigger_field_strategies (
    id bigint CONSTRAINT trs_suite_trigger_field_overrides_id_not_null NOT NULL,
    trigger_txtp_config_id bigint CONSTRAINT trs_suite_trigger_field_overrid_trigger_txtp_config_id_not_null NOT NULL,
    field_path text CONSTRAINT trs_suite_trigger_field_overrides_field_path_not_null NOT NULL,
    strategy_code character varying(24) CONSTRAINT trs_suite_trigger_field_overrides_override_type_not_null NOT NULL,
    static_value jsonb,
    range_min numeric,
    range_max numeric,
    faker_semantic_type character varying(64),
    generator_options jsonb DEFAULT '{}'::jsonb CONSTRAINT trs_suite_trigger_field_overrides_generator_options_not_null NOT NULL,
    created_at timestamp with time zone DEFAULT now() CONSTRAINT trs_suite_trigger_field_overrides_created_at_not_null NOT NULL,
    CONSTRAINT chk_trs_suite_trigger_field_overrides_range CHECK ((((strategy_code)::text <> 'range'::text) OR ((range_min IS NOT NULL) AND (range_max IS NOT NULL) AND (range_min <= range_max)))),
    CONSTRAINT chk_trs_suite_trigger_field_strategy_code CHECK (((strategy_code)::text = ANY (ARRAY[('keep_sample'::character varying)::text, ('static'::character varying)::text, ('range'::character varying)::text, ('skip'::character varying)::text, ('random'::character varying)::text])))
);


--
-- Name: trs_suite_trigger_field_overrides_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_trigger_field_overrides_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_trigger_field_overrides_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_trigger_field_overrides_id_seq OWNED BY public.trs_suite_trigger_field_strategies.id;


--
-- Name: trs_suite_trigger_generated_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_trigger_generated_messages (
    id bigint NOT NULL,
    trigger_txtp_config_id bigint CONSTRAINT trs_suite_trigger_generated_mes_trigger_txtp_config_id_not_null NOT NULL,
    message_order integer NOT NULL,
    payload_json jsonb NOT NULL,
    end_to_end_id character varying(140),
    linked_context_message_id bigint,
    validation_status character varying(16) DEFAULT 'VALID'::character varying NOT NULL,
    validation_errors jsonb,
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT trs_suite_trigger_generated_messages_message_order_check CHECK ((message_order >= 1)),
    CONSTRAINT trs_suite_trigger_generated_messages_validation_status_check CHECK (((validation_status)::text = ANY (ARRAY[('VALID'::character varying)::text, ('INVALID'::character varying)::text])))
);


--
-- Name: trs_suite_trigger_generated_messages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_trigger_generated_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_trigger_generated_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_trigger_generated_messages_id_seq OWNED BY public.trs_suite_trigger_generated_messages.id;


--
-- Name: trs_suite_trigger_txtp_configs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trs_suite_trigger_txtp_configs (
    id bigint NOT NULL,
    generation_id bigint NOT NULL,
    txtp character varying(80) NOT NULL,
    txtp_version character varying(80) NOT NULL,
    display_order integer NOT NULL,
    message_count integer NOT NULL,
    link_to_context_pairs boolean DEFAULT false NOT NULL,
    payload_template_json jsonb NOT NULL,
    expected_independent_variable numeric,
    expected_result_band character varying(16),
    notes text,
    faker_seed bigint,
    generator_profile jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    related_txtp_config_id integer,
    related_transaction text,
    CONSTRAINT chk_trs_suite_trigger_txtp_configs_expected_band CHECK (((expected_result_band IS NULL) OR ((expected_result_band)::text = ANY (ARRAY[('good'::character varying)::text, ('neutral'::character varying)::text, ('bad'::character varying)::text, ('error'::character varying)::text])))),
    CONSTRAINT trs_suite_trigger_txtp_configs_message_count_check CHECK ((message_count >= 1))
);


--
-- Name: trs_suite_trigger_txtp_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trs_suite_trigger_txtp_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trs_suite_trigger_txtp_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trs_suite_trigger_txtp_configs_id_seq OWNED BY public.trs_suite_trigger_txtp_configs.id;


--
-- Name: trs_faker_semantic_data_types id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_faker_semantic_data_types ALTER COLUMN id SET DEFAULT nextval('public.trs_faker_semantic_data_types_id_seq'::regclass);


--
-- Name: trs_mapping id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_mapping ALTER COLUMN id SET DEFAULT nextval('public.trs_mapping_id_seq'::regclass);


--
-- Name: trs_simulation_run_results id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_run_results ALTER COLUMN id SET DEFAULT nextval('public.trs_simulation_run_results_id_seq'::regclass);


--
-- Name: trs_simulation_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_runs ALTER COLUMN id SET DEFAULT nextval('public.trs_simulation_runs_id_seq'::regclass);


--
-- Name: trs_simulation_suites id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_suites ALTER COLUMN id SET DEFAULT nextval('public.trs_simulation_suites_id_seq'::regclass);


--
-- Name: trs_suite_context_field_strategies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_field_strategies ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_context_field_strategies_id_seq'::regclass);


--
-- Name: trs_suite_context_generated_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_generated_messages ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_context_generated_messages_id_seq'::regclass);


--
-- Name: trs_suite_context_sim_pairs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_sim_pairs ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_context_sim_pairs_id_seq'::regclass);


--
-- Name: trs_suite_context_txtp_configs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_txtp_configs ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_context_txtp_configs_id_seq'::regclass);


--
-- Name: trs_suite_enrichment_field_strategies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_field_strategies ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_enrichment_field_strategies_id_seq'::regclass);


--
-- Name: trs_suite_enrichment_generated_rows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_generated_rows ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_enrichment_generated_rows_id_seq'::regclass);


--
-- Name: trs_suite_enrichment_tables id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_tables ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_enrichment_tables_id_seq'::regclass);


--
-- Name: trs_suite_generations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_generations ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_generations_id_seq'::regclass);


--
-- Name: trs_suite_trigger_field_strategies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_field_strategies ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_trigger_field_overrides_id_seq'::regclass);


--
-- Name: trs_suite_trigger_generated_messages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_generated_messages ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_trigger_generated_messages_id_seq'::regclass);


--
-- Name: trs_suite_trigger_txtp_configs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_txtp_configs ALTER COLUMN id SET DEFAULT nextval('public.trs_suite_trigger_txtp_configs_id_seq'::regclass);


--
-- Name: trs_faker_semantic_data_types trs_faker_semantic_data_types_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_faker_semantic_data_types
    ADD CONSTRAINT trs_faker_semantic_data_types_pkey PRIMARY KEY (id);


--
-- Name: trs_mapping trs_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_mapping
    ADD CONSTRAINT trs_mapping_pkey PRIMARY KEY (id);


--
-- Name: trs_simulation_run_result_context_links trs_simulation_run_result_context_links_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_run_result_context_links
    ADD CONSTRAINT trs_simulation_run_result_context_links_pkey PRIMARY KEY (run_result_id, context_message_id);


--
-- Name: trs_simulation_run_results trs_simulation_run_results_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_run_results
    ADD CONSTRAINT trs_simulation_run_results_pkey PRIMARY KEY (id);


--
-- Name: trs_simulation_runs trs_simulation_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_runs
    ADD CONSTRAINT trs_simulation_runs_pkey PRIMARY KEY (id);


--
-- Name: trs_simulation_suites trs_simulation_suites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_suites
    ADD CONSTRAINT trs_simulation_suites_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_context_field_strategies trs_suite_context_field_strategies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_field_strategies
    ADD CONSTRAINT trs_suite_context_field_strategies_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_context_generated_messages trs_suite_context_generated_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_generated_messages
    ADD CONSTRAINT trs_suite_context_generated_messages_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_context_sim_pairs trs_suite_context_sim_pairs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_sim_pairs
    ADD CONSTRAINT trs_suite_context_sim_pairs_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_context_txtp_configs trs_suite_context_txtp_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_txtp_configs
    ADD CONSTRAINT trs_suite_context_txtp_configs_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_enrichment_field_strategies trs_suite_enrichment_field_strategies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_field_strategies
    ADD CONSTRAINT trs_suite_enrichment_field_strategies_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_enrichment_generated_rows trs_suite_enrichment_generated_rows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_generated_rows
    ADD CONSTRAINT trs_suite_enrichment_generated_rows_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_enrichment_tables trs_suite_enrichment_tables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_tables
    ADD CONSTRAINT trs_suite_enrichment_tables_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_generations trs_suite_generations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_generations
    ADD CONSTRAINT trs_suite_generations_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_trigger_field_strategies trs_suite_trigger_field_overrides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_field_strategies
    ADD CONSTRAINT trs_suite_trigger_field_overrides_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_trigger_generated_messages trs_suite_trigger_generated_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_generated_messages
    ADD CONSTRAINT trs_suite_trigger_generated_messages_pkey PRIMARY KEY (id);


--
-- Name: trs_suite_trigger_txtp_configs trs_suite_trigger_txtp_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_txtp_configs
    ADD CONSTRAINT trs_suite_trigger_txtp_configs_pkey PRIMARY KEY (id);


--
-- Name: trs_simulation_runs uq_trs_simulation_runs; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_runs
    ADD CONSTRAINT uq_trs_simulation_runs UNIQUE (suite_id, generation_id);


--
-- Name: trs_suite_context_field_strategies uq_trs_suite_context_field_strategies; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_field_strategies
    ADD CONSTRAINT uq_trs_suite_context_field_strategies UNIQUE (context_txtp_config_id, field_path);


--
-- Name: trs_suite_context_generated_messages uq_trs_suite_context_generated_messages; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_generated_messages
    ADD CONSTRAINT uq_trs_suite_context_generated_messages UNIQUE (context_txtp_config_id, message_order);


--
-- Name: trs_suite_context_sim_pairs uq_trs_suite_context_sim_pairs_message; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_sim_pairs
    ADD CONSTRAINT uq_trs_suite_context_sim_pairs_message UNIQUE (context_message_id, trigger_message_id);


--
-- Name: trs_suite_context_sim_pairs uq_trs_suite_context_sim_pairs_order; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_sim_pairs
    ADD CONSTRAINT uq_trs_suite_context_sim_pairs_order UNIQUE (generation_id, pair_order);


--
-- Name: trs_suite_context_txtp_configs uq_trs_suite_context_txtp_configs; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_txtp_configs
    ADD CONSTRAINT uq_trs_suite_context_txtp_configs UNIQUE (generation_id, txtp, txtp_version, display_order);


--
-- Name: trs_suite_enrichment_field_strategies uq_trs_suite_enrichment_field_strategies; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_field_strategies
    ADD CONSTRAINT uq_trs_suite_enrichment_field_strategies UNIQUE (enrichment_table_id, column_name);


--
-- Name: trs_suite_enrichment_generated_rows uq_trs_suite_enrichment_generated_rows; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_generated_rows
    ADD CONSTRAINT uq_trs_suite_enrichment_generated_rows UNIQUE (enrichment_table_id, row_order);


--
-- Name: trs_suite_enrichment_tables uq_trs_suite_enrichment_tables; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_tables
    ADD CONSTRAINT uq_trs_suite_enrichment_tables UNIQUE (generation_id, table_name);


--
-- Name: trs_suite_generations uq_trs_suite_generations_suite_generation; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_generations
    ADD CONSTRAINT uq_trs_suite_generations_suite_generation UNIQUE (suite_id, generation_number);


--
-- Name: trs_suite_trigger_field_strategies uq_trs_suite_trigger_field_overrides; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_field_strategies
    ADD CONSTRAINT uq_trs_suite_trigger_field_overrides UNIQUE (trigger_txtp_config_id, field_path);


--
-- Name: trs_suite_trigger_generated_messages uq_trs_suite_trigger_generated_messages; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_generated_messages
    ADD CONSTRAINT uq_trs_suite_trigger_generated_messages UNIQUE (trigger_txtp_config_id, message_order);


--
-- Name: trs_suite_trigger_txtp_configs uq_trs_suite_trigger_txtp_configs; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_txtp_configs
    ADD CONSTRAINT uq_trs_suite_trigger_txtp_configs UNIQUE (generation_id, txtp, txtp_version, display_order);


--
-- Name: idx_sim_suites_primary_txtp; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sim_suites_primary_txtp ON public.trs_simulation_suites USING btree (primary_txtp);


--
-- Name: idx_sim_suites_rule; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sim_suites_rule ON public.trs_simulation_suites USING btree (rule_name);


--
-- Name: idx_sim_suites_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sim_suites_status ON public.trs_simulation_suites USING btree (status);


--
-- Name: idx_sim_suites_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sim_suites_tenant ON public.trs_simulation_suites USING btree (tenant_id);


--
-- Name: idx_sim_suites_tenant_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sim_suites_tenant_name ON public.trs_simulation_suites USING btree (tenant_id, name);


--
-- Name: idx_sim_suites_tenant_status_updated; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sim_suites_tenant_status_updated ON public.trs_simulation_suites USING btree (tenant_id, status, updated_at DESC);


--
-- Name: idx_sim_suites_updated; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sim_suites_updated ON public.trs_simulation_suites USING btree (updated_at DESC);


--
-- Name: idx_trs_simulation_run_result_context_links_context; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_simulation_run_result_context_links_context ON public.trs_simulation_run_result_context_links USING btree (context_message_id);


--
-- Name: idx_trs_simulation_run_results_band; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_simulation_run_results_band ON public.trs_simulation_run_results USING btree (sub_rule_ref);


--
-- Name: idx_trs_simulation_run_results_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_simulation_run_results_run_id ON public.trs_simulation_run_results USING btree (run_id);


--
-- Name: idx_trs_simulation_runs_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_simulation_runs_created_at ON public.trs_simulation_runs USING btree (created_at DESC);


--
-- Name: idx_trs_simulation_runs_suite_generation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_simulation_runs_suite_generation ON public.trs_simulation_runs USING btree (suite_id, generation_id);


--
-- Name: idx_trs_suite_context_field_strategies_config_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_context_field_strategies_config_id ON public.trs_suite_context_field_strategies USING btree (context_txtp_config_id);


--
-- Name: idx_trs_suite_context_generated_messages_config_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_context_generated_messages_config_id ON public.trs_suite_context_generated_messages USING btree (context_txtp_config_id);


--
-- Name: idx_trs_suite_context_generated_messages_generated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_context_generated_messages_generated_at ON public.trs_suite_context_generated_messages USING btree (generated_at DESC);


--
-- Name: idx_trs_suite_context_sim_pairs_generation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_context_sim_pairs_generation_id ON public.trs_suite_context_sim_pairs USING btree (generation_id);


--
-- Name: idx_trs_suite_context_txtp_configs_generation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_context_txtp_configs_generation_id ON public.trs_suite_context_txtp_configs USING btree (generation_id);


--
-- Name: idx_trs_suite_enrichment_field_strategies_table_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_enrichment_field_strategies_table_id ON public.trs_suite_enrichment_field_strategies USING btree (enrichment_table_id);


--
-- Name: idx_trs_suite_enrichment_generated_rows_table_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_enrichment_generated_rows_table_id ON public.trs_suite_enrichment_generated_rows USING btree (enrichment_table_id);


--
-- Name: idx_trs_suite_enrichment_tables_generation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_enrichment_tables_generation_id ON public.trs_suite_enrichment_tables USING btree (generation_id);


--
-- Name: idx_trs_suite_generations_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_generations_created_at ON public.trs_suite_generations USING btree (created_at DESC);


--
-- Name: idx_trs_suite_generations_suite_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_generations_suite_id ON public.trs_suite_generations USING btree (suite_id);


--
-- Name: idx_trs_suite_trigger_field_overrides_config_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_trigger_field_overrides_config_id ON public.trs_suite_trigger_field_strategies USING btree (trigger_txtp_config_id);


--
-- Name: idx_trs_suite_trigger_generated_messages_config_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_trigger_generated_messages_config_id ON public.trs_suite_trigger_generated_messages USING btree (trigger_txtp_config_id);


--
-- Name: idx_trs_suite_trigger_generated_messages_e2e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_trigger_generated_messages_e2e ON public.trs_suite_trigger_generated_messages USING btree (end_to_end_id);


--
-- Name: idx_trs_suite_trigger_txtp_configs_generation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_trs_suite_trigger_txtp_configs_generation_id ON public.trs_suite_trigger_txtp_configs USING btree (generation_id);


--
-- Name: trs_simulation_runs trg_trs_simulation_runs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_trs_simulation_runs_updated_at BEFORE UPDATE ON public.trs_simulation_runs FOR EACH ROW EXECUTE FUNCTION public.trs_set_updated_at();


--
-- Name: trs_simulation_suites trg_trs_simulation_suites_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_trs_simulation_suites_updated_at BEFORE UPDATE ON public.trs_simulation_suites FOR EACH ROW EXECUTE FUNCTION public.trs_set_updated_at();


--
-- Name: trs_suite_generations trg_trs_suite_generations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_trs_suite_generations_updated_at BEFORE UPDATE ON public.trs_suite_generations FOR EACH ROW EXECUTE FUNCTION public.trs_set_updated_at();


--
-- Name: trs_simulation_run_result_context_links trs_simulation_run_result_context_links_context_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_run_result_context_links
    ADD CONSTRAINT trs_simulation_run_result_context_links_context_message_id_fkey FOREIGN KEY (context_message_id) REFERENCES public.trs_suite_context_generated_messages(id) ON DELETE CASCADE;


--
-- Name: trs_simulation_run_result_context_links trs_simulation_run_result_context_links_run_result_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_run_result_context_links
    ADD CONSTRAINT trs_simulation_run_result_context_links_run_result_id_fkey FOREIGN KEY (run_result_id) REFERENCES public.trs_simulation_run_results(id) ON DELETE CASCADE;


--
-- Name: trs_simulation_suites trs_simulation_suites_clone_source_suite_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_simulation_suites
    ADD CONSTRAINT trs_simulation_suites_clone_source_suite_id_fkey FOREIGN KEY (clone_source_suite_id) REFERENCES public.trs_simulation_suites(id);


--
-- Name: trs_suite_context_field_strategies trs_suite_context_field_strategies_context_txtp_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_field_strategies
    ADD CONSTRAINT trs_suite_context_field_strategies_context_txtp_config_id_fkey FOREIGN KEY (context_txtp_config_id) REFERENCES public.trs_suite_context_txtp_configs(id) ON DELETE CASCADE;


--
-- Name: trs_suite_context_generated_messages trs_suite_context_generated_message_context_txtp_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_generated_messages
    ADD CONSTRAINT trs_suite_context_generated_message_context_txtp_config_id_fkey FOREIGN KEY (context_txtp_config_id) REFERENCES public.trs_suite_context_txtp_configs(id) ON DELETE CASCADE;


--
-- Name: trs_suite_context_sim_pairs trs_suite_context_sim_pairs_context_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_sim_pairs
    ADD CONSTRAINT trs_suite_context_sim_pairs_context_message_id_fkey FOREIGN KEY (context_message_id) REFERENCES public.trs_suite_context_generated_messages(id) ON DELETE CASCADE;


--
-- Name: trs_suite_context_sim_pairs trs_suite_context_sim_pairs_generation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_sim_pairs
    ADD CONSTRAINT trs_suite_context_sim_pairs_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES public.trs_suite_generations(id) ON DELETE CASCADE;


--
-- Name: trs_suite_context_sim_pairs trs_suite_context_sim_pairs_trigger_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_sim_pairs
    ADD CONSTRAINT trs_suite_context_sim_pairs_trigger_message_id_fkey FOREIGN KEY (trigger_message_id) REFERENCES public.trs_suite_trigger_generated_messages(id) ON DELETE CASCADE;


--
-- Name: trs_suite_context_txtp_configs trs_suite_context_txtp_configs_generation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_context_txtp_configs
    ADD CONSTRAINT trs_suite_context_txtp_configs_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES public.trs_suite_generations(id) ON DELETE CASCADE;


--
-- Name: trs_suite_enrichment_field_strategies trs_suite_enrichment_field_strategies_enrichment_table_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_field_strategies
    ADD CONSTRAINT trs_suite_enrichment_field_strategies_enrichment_table_id_fkey FOREIGN KEY (enrichment_table_id) REFERENCES public.trs_suite_enrichment_tables(id) ON DELETE CASCADE;


--
-- Name: trs_suite_enrichment_generated_rows trs_suite_enrichment_generated_rows_enrichment_table_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_generated_rows
    ADD CONSTRAINT trs_suite_enrichment_generated_rows_enrichment_table_id_fkey FOREIGN KEY (enrichment_table_id) REFERENCES public.trs_suite_enrichment_tables(id) ON DELETE CASCADE;


--
-- Name: trs_suite_enrichment_tables trs_suite_enrichment_tables_generation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_enrichment_tables
    ADD CONSTRAINT trs_suite_enrichment_tables_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES public.trs_suite_generations(id) ON DELETE CASCADE;


--
-- Name: trs_suite_generations trs_suite_generations_suite_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_generations
    ADD CONSTRAINT trs_suite_generations_suite_id_fkey FOREIGN KEY (suite_id) REFERENCES public.trs_simulation_suites(id) ON DELETE CASCADE;


--
-- Name: trs_suite_trigger_field_strategies trs_suite_trigger_field_overrides_trigger_txtp_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_field_strategies
    ADD CONSTRAINT trs_suite_trigger_field_overrides_trigger_txtp_config_id_fkey FOREIGN KEY (trigger_txtp_config_id) REFERENCES public.trs_suite_trigger_txtp_configs(id) ON DELETE CASCADE;


--
-- Name: trs_suite_trigger_generated_messages trs_suite_trigger_generated_mess_linked_context_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_generated_messages
    ADD CONSTRAINT trs_suite_trigger_generated_mess_linked_context_message_id_fkey FOREIGN KEY (linked_context_message_id) REFERENCES public.trs_suite_context_generated_messages(id);


--
-- Name: trs_suite_trigger_generated_messages trs_suite_trigger_generated_message_trigger_txtp_config_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_generated_messages
    ADD CONSTRAINT trs_suite_trigger_generated_message_trigger_txtp_config_id_fkey FOREIGN KEY (trigger_txtp_config_id) REFERENCES public.trs_suite_trigger_txtp_configs(id) ON DELETE CASCADE;


--
-- Name: trs_suite_trigger_txtp_configs trs_suite_trigger_txtp_configs_generation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trs_suite_trigger_txtp_configs
    ADD CONSTRAINT trs_suite_trigger_txtp_configs_generation_id_fkey FOREIGN KEY (generation_id) REFERENCES public.trs_suite_generations(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--


