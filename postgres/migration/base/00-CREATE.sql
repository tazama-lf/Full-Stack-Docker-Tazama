create database configuration;

create database event_history;

create database raw_history;

create database evaluation;

\connect configuration;

create table network_map (configuration jsonb not null);

create table typology (
    configuration jsonb not null,
    typologyId text generated always as (configuration ->> 'id') stored,
    typologyCfg text generated always as (configuration ->> 'cfg') stored,
    unique (typologyId, typologyCfg)
);

create table rule (
    configuration jsonb not null,
    ruleId text generated always as (configuration ->> 'id') stored,
    ruleCfg text generated always as (configuration ->> 'cfg') stored,
    unique (ruleId, ruleCfg)
);

\connect evaluation;

create table evaluation (
    evaluation jsonb not null,
    messageId text generated always as (
        evaluation -> 'transaction' -> 'FIToFIPmtSts' -> 'GrpHdr' ->> 'MsgId'
    ) stored
);

\connect event_history;

create table account (id varchar primary key);

create table entity (
    id varchar primary key,
    creDtTm timestamptz not null
);

create table account_holder (
    source varchar references entity (id),
    destination varchar references account (id),
    creDtTm timestamptz not null,
    primary key (source, destination)
);

create table condition (
    id varchar primary key generated always as (condition ->> 'condId') stored,
    condition jsonb not null
);

create table governed_as_creditor_account_by (
    id serial,
    source varchar references account(id),
    destination varchar references condition(id),
    evtTp text [] not null,
    incptnDtTm timestamptz not null,
    xprtnDtTm timestamptz,
    primary key (id, source, destination)
);

create table governed_as_creditor_by (
    id serial,
    source varchar references entity(id),
    destination varchar references condition(id),
    evtTp TEXT [] not null,
    incptnDtTm timestamptz not null,
    xprtnDtTm timestamptz,
    primary key (id, source, destination)
);

create table governed_as_debtor_account_by (
    id serial,
    source varchar references account(id),
    destination varchar references condition(id),
    evtTp TEXT [] not null,
    incptnDtTm timestamptz not null,
    xprtnDtTm timestamptz,
    primary key (id, source, destination)
);

create table governed_as_debtor_by (
    id serial,
    source varchar references entity(id),
    destination varchar references condition(id),
    evtTp TEXT [] not null,
    incptnDtTm timestamptz not null,
    xprtnDtTm timestamptz,
    primary key (id, source, destination)
);
/* transaction_relationship*/
create table transaction (
    source varchar references account(id),
    destination varchar references account(id),
    transaction jsonb not null,
    endToEndId text generated always as (transaction->>'EndToEndId') stored,
    amt numeric(18, 2) generated always as (
        (transaction->>'Amt')::numeric(18, 2)
    ) stored,
    ccy varchar generated always as (transaction->>'Ccy') stored,
    msgId varchar generated always as (transaction->>'MsgId') stored,
    creDtTm text generated always as (transaction->>'CreDtTm') stored,
    txTp varchar generated always as (transaction->>'TxTp') stored,
    txSts varchar generated always as (transaction->>'TxSts') stored,
    primary key (msgId, endToEndId, txTp)
);

create index idx_tr_e2d_txtp on transaction (endToEndId, txTp);

create index idx_tr_cre_dt_tm on transaction (creDtTm);

create index idx_tr_source_txtp_credttm ON transaction (source, txtp, creDtTm);

create index idx_tr_txsts on transaction (txsts);

create index idx_tr_endtoendid on transaction (endtoendid);

create index idx_tr_pacs002_accc on transaction (endtoendid, creDtTm)
where
    txtp = 'pacs.002.001.12'
    and txsts = 'ACCC';

create index idx_tr_dest_txtp_txsts_credttm on transaction (
    destination,
    txtp,
    txsts,
    creDtTm desc
) include (source);

\connect raw_history;

create table pacs002 (
    document jsonb not null,
    -- cast when querying
    creDtTm text generated always as (
        document -> 'FIToFIPmtSts' -> 'GrpHdr' ->> 'CreDtTm'
    ) stored,
    messageId text generated always as (
        document -> 'FIToFIPmtSts' -> 'GrpHdr' ->> 'MsgId'
    ) stored,
    endToEndId text generated always as (
        document -> 'FIToFIPmtSts' -> 'TxInfAndSts' ->> 'OrgnlEndToEndId'
    ) stored,
    constraint unique_e2eid_pacs002 unique (endToEndId),
    constraint unique_msgid_pacs002 unique (messageId),
    constraint message_id_not_null check (messageId is not null),
    constraint cre_dt_tm check (creDtTm is not null),
    constraint end_to_end_id_not_null check (endToEndId is not null)
);

create index idx_pacs002_msg_id on pacs002 (messageId);

create index idx_pacs002_end_to_end_id on pacs002 (endToEndId);

create table pacs008 (
    document jsonb not null,
    -- cast when querying
    creDtTm text generated always as (
        document -> 'FIToFICstmrCdtTrf' -> 'GrpHdr' ->> 'CreDtTm'
    ) stored,
    messageId text generated always as (
        document -> 'FIToFICstmrCdtTrf' -> 'GrpHdr' ->> 'MsgId'
    ) stored,
    endToEndId text generated always as (
        document -> 'FIToFICstmrCdtTrf' -> 'CdtTrfTxInf' -> 'PmtId' ->> 'EndToEndId'
    ) stored,
    debtorAccountId text generated always as (
        document -> 'FIToFICstmrCdtTrf' -> 'CdtTrfTxInf' -> 'DbtrAcct' -> 'Id' -> 'Othr' -> 0 ->> 'Id'
    ) stored,
    creditorAccountId text generated always as (
        document -> 'FIToFICstmrCdtTrf' -> 'CdtTrfTxInf' -> 'CdtrAcct' -> 'Id' -> 'Othr' -> 0 ->> 'Id'
    ) stored,
    constraint unique_msgid_e2eid_pacs008 unique (messageId, endToEndId),
    constraint unique_e2eid_pacs008 unique (endToEndId),
    constraint message_id_not_null check (messageId is not null),
    constraint cre_dt_tm check (creDtTm is not null),
    constraint dbtr_acct_id_not_null check (debtorAccountId is not null),
    constraint cdtr_acct_id_not_null check (creditorAccountId is not null),
    constraint end_to_end_id_not_null check (endToEndId is not null)
);

create index idx_pacs008_msg_id on pacs008 (messageId);

create index idx_pacs008_end_to_end_id on pacs008 (endToEndId);

create index idx_pacs008_dbtr_acct_id on pacs008 (debtorAccountId);

create index idx_pacs008_cdtr_acct_id on pacs008 (creditorAccountId);

create index idx_pacs008_credttm on pacs008 (creDtTm);