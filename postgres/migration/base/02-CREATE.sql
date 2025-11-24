\connect configuration;

create table network_map (
    configuration jsonb not null,
    tenantId text not null default public.current_tenant_id(),
    foreign key (tenantId) references tenant(id) on delete cascade
);

create index on network_map (tenantId);
alter table network_map enable row level security;

create policy nmap_tenant_isolation on network_map
  for all
  to public
  using (public.has_tenant(tenantId, current_user));

create table typology (
    configuration jsonb not null,
    typologyId text generated always as (configuration ->> 'id') stored,
    typologyCfg text generated always as (configuration ->> 'cfg') stored,
    tenantId text not null default public.current_tenant_id(),
    foreign key (tenantId) references tenant(id) on delete cascade,
    primary key (typologyId, typologyCfg, tenantId)
);

create index on typology (tenantId);
alter table typology enable row level security;

create policy typology_tenant_isolation on typology
  for select
  to public
  using (public.has_tenant(tenantId, current_user));


create table rule (
    configuration jsonb not null,
    ruleId text generated always as (configuration ->> 'id') stored,
    ruleCfg text generated always as (configuration ->> 'cfg') stored,
    tenantId text not null default public.current_tenant_id(),
    foreign key (tenantId) references tenant(id) on delete cascade,
    primary key (ruleId, ruleCfg, tenantId)
);

create index on rule (tenantId);
alter table rule enable row level security;

create policy rule_tenant_isolation on rule
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

\connect evaluation;

create table evaluation (
    evaluation jsonb not null,
    messageId text generated always as (
        evaluation -> 'transaction' -> 'FIToFIPmtSts' -> 'GrpHdr' ->> 'MsgId'
    ) stored,
    tenantId text not null default public.current_tenant_id(),
    foreign key (tenantId) references tenant(id) on delete cascade,
    constraint unique_msgid_evaluation unique (messageId, tenantId)
);

create index on evaluation (tenantId);
alter table evaluation enable row level security;

create policy evaluation_tenant_isolation on evaluation
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

\connect event_history;

create table account (
    id varchar not null,
    tenantId text not null default public.current_tenant_id(),
    foreign key (tenantId) references tenant(id) on delete cascade,
    primary key (id, tenantId)
);

create index on account (tenantId);
alter table account enable row level security;

create policy account_tenant_isolation on account
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

create table entity (
    id varchar not null,
    tenantId text not null default public.current_tenant_id(),
    creDtTm timestamptz not null,
    foreign key (tenantId) references tenant(id) on delete cascade,
    primary key (id, tenantId)
);

create index on entity (tenantId);
alter table entity enable row level security;

create policy entity_tenant_isolation on entity
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

create table account_holder (
    source varchar not null,
    destination varchar not null,
    tenantId text not null default public.current_tenant_id(),
    creDtTm timestamptz not null,
    foreign key (source, tenantId) references entity (id, tenantId),
    foreign key (destination, tenantId) references account (id, tenantId),
    foreign key (tenantId) references tenant(id) on delete cascade,
    primary key (source, destination, tenantId)
);

create index on account_holder (tenantId);
alter table account_holder enable row level security;

create policy account_holder_tenant_isolation on account_holder
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

create table condition (
    id varchar generated always as (condition ->> 'condId') stored,
    tenantId text not null default public.current_tenant_id(),
    condition jsonb not null,
    foreign key (tenantId) references tenant(id) on delete cascade,
    primary key (id, tenantId)
);

create index on condition (tenantId);
alter table condition enable row level security;

create policy condition_tenant_isolation on condition
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

create table governed_as_creditor_account_by (
    source varchar not null,
    destination varchar not null,
    evtTp text [] not null,
    incptnDtTm timestamptz not null,
    xprtnDtTm timestamptz,
    tenantId text not null default public.current_tenant_id(),
    foreign key (source, tenantId) references account (id, tenantId),
    foreign key (tenantId) references tenant(id) on delete cascade,
    foreign key (destination, tenantId) references condition (id, tenantId),
    primary key (source, destination, tenantId)
);

create index on governed_as_creditor_account_by (tenantId);
alter table governed_as_creditor_account_by enable row level security;

create policy gv_cred_acct_tenant_isolation on governed_as_creditor_account_by
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

create table governed_as_creditor_by (
    source varchar not null,
    destination varchar not null,
    evtTp TEXT [] not null,
    incptnDtTm timestamptz not null,
    xprtnDtTm timestamptz,
    tenantId text not null default public.current_tenant_id(),
    foreign key (source, tenantId) references entity (id, tenantId),
    foreign key (tenantId) references tenant(id) on delete cascade,
    foreign key (destination, tenantId) references condition (id, tenantId),
    primary key (source, destination, tenantId)
);

create index on governed_as_creditor_by (tenantId);
alter table governed_as_creditor_by enable row level security;

create policy gv_cred_tenant_isolation on governed_as_creditor_by
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

create table governed_as_debtor_account_by (
    source varchar not null,
    destination varchar not null,
    evtTp TEXT [] not null,
    incptnDtTm timestamptz not null,
    xprtnDtTm timestamptz,
    tenantId text not null default public.current_tenant_id(),
    foreign key (source, tenantId) references account (id, tenantId),
    foreign key (tenantId) references tenant(id) on delete cascade,
    foreign key (destination, tenantId) references condition (id, tenantId),
    primary key (source, destination, tenantId)
);

create index on governed_as_debtor_account_by (tenantId);
alter table governed_as_debtor_account_by enable row level security;

create policy gv_dbtr_acct_tenant_isolation on governed_as_debtor_account_by
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

create table governed_as_debtor_by (
    source varchar not null,
    destination varchar not null,
    evtTp TEXT [] not null,
    incptnDtTm timestamptz not null,
    xprtnDtTm timestamptz,
    tenantId text not null default public.current_tenant_id(),
    foreign key (source, tenantId) references entity (id, tenantId),
    foreign key (tenantId) references tenant(id) on delete cascade,
    foreign key (destination, tenantId) references condition (id, tenantId),
    primary key (source, destination, tenantId)
);

create index on governed_as_debtor_by (tenantId);
alter table governed_as_debtor_by enable row level security;

create policy gv_dbtr_tenant_isolation on governed_as_debtor_by
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

/* transaction_relationship*/
create table transaction (
    source varchar not null,
    destination varchar not null,
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
    tenantId text not null default public.current_tenant_id(),
    constraint unique_msgid unique (msgId, tenantId),
    foreign key (tenantId) references tenant(id) on delete cascade,
    foreign key (source, tenantId) references account (id, tenantId),
    foreign key (destination, tenantId) references account (id, tenantId),
    primary key (endToEndId, txTp, tenantId)
);

create index on transaction (tenantId);

create index idx_tr_cre_dt_tm on transaction (creDtTm, tenantId);

create index idx_tr_source_txtp_credttm ON transaction (source, txtp, creDtTm, tenantId);


create index idx_tr_pacs002_accc on transaction (endtoendid, creDtTm, tenantId)
where
    txtp = 'pacs.002.001.12'
    and txsts = 'ACCC';

create index idx_tr_dest_txtp_txsts_credttm on transaction (
    destination,
    txtp,
    txsts,
    creDtTm desc
) include (source);

alter table transaction enable row level security;

create policy tx_tenant_isolation on transaction
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

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
    tenantId text not null default public.current_tenant_id(),
    foreign key (tenantId) references tenant(id) on delete cascade,
    constraint unique_msgid_pacs002 unique (messageId, tenantId),
    constraint message_id_not_null check (messageId is not null),
    constraint cre_dt_tm check (creDtTm is not null),
    primary key (endToEndId, tenantId)
);

create index on pacs002 (tenantId);
alter table pacs002 enable row level security;

create policy pacs002_tenant_isolation on pacs002
  for select
  to public
  using (public.has_tenant(tenantId, current_user));


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
    tenantId text not null default public.current_tenant_id(),
    constraint unique_msgid_e2eid_pacs008 unique (messageId, tenantId),
    constraint message_id_not_null check (messageId is not null),
    constraint cre_dt_tm check (creDtTm is not null),
    constraint dbtr_acct_id_not_null check (debtorAccountId is not null),
    constraint cdtr_acct_id_not_null check (creditorAccountId is not null),
    foreign key (tenantId) references tenant(id) on delete cascade,
    primary key (endToEndId, tenantId)
);

create index on pacs008 (tenantId);
alter table pacs008 enable row level security;

create policy pacs008_tenant_isolation on pacs008
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

create index idx_pacs008_dbtr_acct_id on pacs008 (debtorAccountId, tenantId);

create index idx_pacs008_cdtr_acct_id on pacs008 (creditorAccountId, tenantId);

create index idx_pacs008_credttm on pacs008 (creDtTm, tenantId);

create table pain001 (
    document jsonb not null,
    -- cast when querying
    creDtTm text generated always as (
        document -> 'CstmrCdtTrfInitn' -> 'GrpHdr' ->> 'CreDtTm'
    ) stored,
    messageId text generated always as (
        document -> 'CstmrCdtTrfInitn' -> 'GrpHdr' ->> 'MsgId'
    ) stored,
    endToEndId text generated always as (
        document -> 'CstmrCdtTrfInitn' -> 'PmtInf' -> 'CdtTrfTxInf' -> 'PmtId' ->> 'EndToEndId'
    ) stored,
    debtorAccountId text generated always as (
        document -> 'CstmrCdtTrfInitn' -> 'PmtInf' -> 'DbtrAcct' -> 'Id' -> 'Othr' -> 0 ->> 'Id'
    ) stored,
    creditorAccountId text generated always as (
        document -> 'CstmrCdtTrfInitn' -> 'PmtInf' -> 'CdtTrfTxInf' -> 'CdtrAcct' -> 'Id' -> 'Othr' -> 0 ->> 'Id'
    ) stored,
    tenantId text not null default public.current_tenant_id(),
    constraint unique_msgid_e2eid_pain001 unique (messageId, tenantId),
    constraint message_id_not_null check (messageId is not null),
    constraint cre_dt_tm check (creDtTm is not null),
    constraint dbtr_acct_id_not_null check (debtorAccountId is not null),
    constraint cdtr_acct_id_not_null check (creditorAccountId is not null),
    foreign key (tenantId) references tenant(id) on delete cascade,
    primary key (endToEndId, tenantId)
);

create index on pain001 (tenantId);
alter table pain001 enable row level security;

create policy pain001_tenant_isolation on pain001
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

create index idx_pain001_dbtr_acct_id on pain001 (debtorAccountId, tenantId);

create index idx_pain001_cdtr_acct_id on pain001 (creditorAccountId, tenantId);

create index idx_pain001_credttm on pain001 (creDtTm, tenantId);

create table pain013 (
    document jsonb not null,
    -- cast when querying
    creDtTm text generated always as (
        document -> 'CdtrPmtActvtnReq' -> 'GrpHdr' ->> 'CreDtTm'
    ) stored,
    messageId text generated always as (
        document -> 'CdtrPmtActvtnReq' -> 'GrpHdr' ->> 'MsgId'
    ) stored,
    endToEndId text generated always as (
        document -> 'CdtrPmtActvtnReq' -> 'PmtInf' -> 'CdtTrfTxInf' -> 'PmtId' ->> 'EndToEndId'
    ) stored,
    debtorAccountId text generated always as (
        document -> 'CdtrPmtActvtnReq' -> 'PmtInf' -> 'DbtrAcct' -> 'Id' -> 'Othr' -> 0 ->> 'Id'
    ) stored,
    creditorAccountId text generated always as (
        document -> 'CdtrPmtActvtnReq' -> 'PmtInf' -> 'CdtTrfTxInf' -> 'CdtrAcct' -> 'Id' -> 'Othr' -> 0 ->> 'Id'
    ) stored,
    tenantId text not null default public.current_tenant_id(),
    constraint unique_msgid_e2eid_pain013 unique (messageId, tenantId),
    constraint message_id_not_null check (messageId is not null),
    constraint cre_dt_tm check (creDtTm is not null),
    constraint dbtr_acct_id_not_null check (debtorAccountId is not null),
    constraint cdtr_acct_id_not_null check (creditorAccountId is not null),
    foreign key (tenantId) references tenant(id) on delete cascade,
    primary key (endToEndId, tenantId)
);

create index on pain013 (tenantId);
alter table pain013 enable row level security;

create policy pain013_tenant_isolation on pain013
  for select
  to public
  using (public.has_tenant(tenantId, current_user));

create index idx_pain013_dbtr_acct_id on pain013 (debtorAccountId, tenantId);

create index idx_pain013_cdtr_acct_id on pain013 (creditorAccountId, tenantId);

create index idx_pain013_credttm on pain013 (creDtTm, tenantId);
