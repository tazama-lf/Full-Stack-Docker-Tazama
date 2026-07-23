\connect configuration;

CREATE SEQUENCE IF NOT EXISTS tazama_data_model_json_id_seq;

CREATE TABLE IF NOT EXISTS tazama_data_model_json
(
    id integer NOT NULL DEFAULT nextval('tazama_data_model_json_id_seq'::regclass),
    tenant_id character varying(255) COLLATE pg_catalog."default" NOT NULL,
    data_model_json jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT tazama_data_model_json_pkey PRIMARY KEY (id),
    CONSTRAINT tazama_data_model_json_tenant_id_key UNIQUE (tenant_id)
);


INSERT INTO tazama_data_model_json(id, tenant_id, data_model_json, created_at, updated_at) VALUES 
(1, 'DEFAULT', '{"redis": {"name": "", "evtId": "", "cdtrId": "", "dbtrId": "", "creDtTm": "", "currency": "", "instdAmt": {"Amt": 0, "Ccy": ""}, "xchgRate": 0, "cdtrAcctId": "", "dbtrAcctId": "", "intrBkSttlmAmt": {"Amt": 0, "Ccy": ""}}, "transactionDetails": {"Amt": 0, "Ccy": "", "lat": "", "TxTp": "", "long": "", "MsgId": "", "TxSts": "", "source": "", "CreDtTm": "", "TenantId": "", "EndToEndId": "", "destination": ""}}', NOW(), NOW());


CREATE TABLE IF NOT EXISTS tcs_config (
    id SERIAL PRIMARY KEY,
    msg_fam VARCHAR(255) NOT NULL,
    transaction_type VARCHAR(255) NOT NULL,
    endpoint_path VARCHAR(255) NOT NULL,
    version VARCHAR(255) NOT NULL DEFAULT 'v1',
    content_type VARCHAR(255) NOT NULL DEFAULT 'application/json',
    schema JSONB NOT NULL,
    mapping JSONB,
    tenant_id VARCHAR(255) NOT NULL,
    created_by VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(255) NOT NULL DEFAULT 'inprogress',
    functions JSONB,
    publishing_status VARCHAR(8) DEFAULT 'active',
    comments TEXT,
    payload_json JSONB,
    payload_xml xml,
    related_transaction TEXT
);

CREATE TABLE IF NOT EXISTS tcs_cron_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), 
    tenant_id VARCHAR(100) NOT NULL, 
    name VARCHAR(255) NOT NULL, 
    cron VARCHAR(255) NOT NULL, 
    iterations INTEGER NOT NULL, 
    status VARCHAR(50) NOT NULL DEFAULT 'STATUS_01_IN_PROGRESS' CHECK (status IN ('STATUS_01_IN_PROGRESS','STATUS_02_ON_HOLD','STATUS_03_UNDER_REVIEW','STATUS_04_APPROVED','STATUS_05_REJECTED','STATUS_06_EXPORTED','STATUS_07_READY_FOR_DEPLOYMENT','STATUS_08_DEPLOYED')), 
    created_at TIMESTAMP NOT NULL DEFAULT NOW(), 
    comments TEXT, 
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(), 
    CONSTRAINT cron_jobs_name_tenant_unique UNIQUE (name, tenant_id)
);

CREATE TABLE IF NOT EXISTS tcs_pull_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id character varying(100) NOT NULL,
    endpoint_name character varying(255) NOT NULL,
    schedule_id uuid NOT NULL,
    source_type character varying(50) NOT NULL,
    description text NOT NULL,
    connection jsonb NOT NULL,
    file jsonb,
    table_name character varying(255) NOT NULL,
    mode character varying(50) DEFAULT 'append'::character varying NOT NULL,
    version character varying(50) NOT NULL,
    status character varying(50) DEFAULT 'STATUS_01_IN_PROGRESS'::character varying NOT NULL,
    publishing_status character varying(20) DEFAULT 'in-active'::character varying NOT NULL,
    comments text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT tcs_pull_jobs_pkey PRIMARY KEY (id),
    CONSTRAINT unique_tenant_endpoint_version UNIQUE (tenant_id, endpoint_name, version),
    CONSTRAINT tcs_pull_jobs_mode_check CHECK (mode IN ('append', 'replace')),
    CONSTRAINT tcs_pull_jobs_publishing_status_check CHECK (publishing_status IN ('active', 'in-active')),
    CONSTRAINT tcs_pull_jobs_source_type_check CHECK (source_type IN ('HTTP', 'SFTP')),
    CONSTRAINT tcs_pull_jobs_status_check CHECK (status IN ('STATUS_01_IN_PROGRESS', 'STATUS_02_ON_HOLD', 'STATUS_03_UNDER_REVIEW', 'STATUS_04_APPROVED', 'STATUS_05_REJECTED', 'STATUS_06_EXPORTED', 'STATUS_07_READY_FOR_DEPLOYMENT', 'STATUS_08_DEPLOYED')),
    CONSTRAINT tcs_pull_jobs_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES public.tcs_cron_jobs(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS tcs_push_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id character varying(100) NOT NULL,
    endpoint_name character varying(255) NOT NULL,
    path character varying(255) NOT NULL,
    mode character varying(50) NOT NULL,
    table_name character varying(255) NOT NULL,
    description text,
    version character varying(50) DEFAULT 'v1'::character varying NOT NULL,
    status character varying(50) DEFAULT 'STATUS_01_IN_PROGRESS'::character varying NOT NULL,
    publishing_status character varying(20) DEFAULT 'in-active'::character varying NOT NULL,
    comments text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT tcs_push_jobs_pkey PRIMARY KEY (id),
    CONSTRAINT unique_push_job_version UNIQUE (tenant_id, path, version),
    CONSTRAINT tcs_push_jobs_publishing_status_check CHECK (publishing_status IN ('active', 'in-active')),
    CONSTRAINT tcs_push_jobs_status_check CHECK (status IN ('STATUS_01_IN_PROGRESS', 'STATUS_02_ON_HOLD', 'STATUS_03_UNDER_REVIEW', 'STATUS_04_APPROVED', 'STATUS_05_REJECTED', 'STATUS_06_EXPORTED', 'STATUS_07_READY_FOR_DEPLOYMENT', 'STATUS_08_DEPLOYED'))
);

CREATE TABLE IF NOT EXISTS job_history ( 
    id SERIAL PRIMARY KEY, 
    tenant_id TEXT NOT NULL, 
    job_id UUID NOT NULL, 
    counts INTEGER, 
    processed_counts INTEGER, 
    exception TEXT, 
    job_type TEXT, 
    created_at TIMESTAMP DEFAULT NOW() 
);

CREATE OR REPLACE PROCEDURE rotate_table_with_data(
    original_table TEXT,
    rows_json JSONB
)
LANGUAGE plpgsql
AS $$
DECLARE
    ts TEXT;
    new_table TEXT;
    backup_table TEXT;
BEGIN
    -- timestamp suffix: 20251127_183015
    ts := to_char(NOW(), 'YYYYMMDD_HH24MISS');

    new_table := original_table || '_' || ts;
    backup_table := original_table || '_backup_' || ts;

    EXECUTE format(
        'CREATE TABLE %I (LIKE %I INCLUDING ALL)', 
        new_table, original_table
    );

    EXECUTE format(
        'INSERT INTO %I (data, job_id, checksum)
         SELECT  data, job_id, checksum
         FROM jsonb_to_recordset($1) AS x(
             data JSONB,
             job_id TEXT,
             checksum TEXT,
			 created_at TIMESTAMP
         )',
        new_table
    ) USING rows_json;

    EXECUTE format('ALTER TABLE %I RENAME TO %I', original_table, backup_table);

    EXECUTE format('ALTER TABLE %I RENAME TO %I', new_table, original_table);
END;
$$;
