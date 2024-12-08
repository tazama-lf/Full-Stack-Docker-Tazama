// SPDX-License-Identifier: Apache-2.0

const systemDb = "_system";

/*** CONFIGURATION ***/
// Config DB
const configDbName = "configuration";
// Config Collections
const ruleConfigColName = "ruleConfiguration";
const typologyConfigColName = "typologyConfiguration";
const networkConfigColName = "networkConfiguration";

// Config Setup
db._useDatabase(systemDb);
db._createDatabase(configDbName);
db._useDatabase(configDbName);
db._create(ruleConfigColName);
db._create(typologyConfigColName);
db._create(networkConfigColName);

/*** EVALUATION RESULTS ***/
// Evaluation Results DB
const evaluationsDbName = "evaluationResults";
// Transactions Collections
const transactionsColName = "transactions";
// Transactions Setup
db._useDatabase(systemDb);
db._createDatabase(evaluationsDbName);
db._useDatabase(evaluationsDbName);
db._create(transactionsColName);

/*** PSEUDONYMS ***/
// Pseudonyms DB
const pseudonymsDbName = "pseudonyms";
// Pseudonyms Collections
const pseudonymsColName = "pseudonyms";
const accountHolderColName = "account_holder";
const accountsColName = "accounts";
const entitiesColName = "entities";
const transRelationshipColName = "transactionRelationship";
// Conditions Collections
const conditionsColName = "conditions";
const conditionsDebtorColName = "governed_as_debtor_by";
const conditionsDebtorAccountColName = "governed_as_debtor_account_by";
const conditionsCreditorName = "governed_as_creditor_by";
const conditionsCreditorAccountName = "governed_as_creditor_account_by";

db._useDatabase(systemDb);
db._createDatabase(pseudonymsDbName);
db._useDatabase(pseudonymsDbName);
db._create(pseudonymsColName);
db._createEdgeCollection(accountHolderColName);
db._create(accountsColName);
db._create(entitiesColName);
db._createEdgeCollection(transRelationshipColName);
db._create(conditionsColName);
db._createEdgeCollection(conditionsDebtorColName);
db._createEdgeCollection(conditionsDebtorAccountColName);
db._createEdgeCollection(conditionsCreditorName);
db._createEdgeCollection(conditionsCreditorAccountName);

// Pseudonyms Indices
db._collection(entitiesColName).ensureIndex({
  type: "persistent",
  fields: ["Id"],
  name: "pi_Id",
  unique: false,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: false,
  inBackground: false,
});

db._collection(pseudonymsColName).ensureIndex({
  type: "persistent",
  fields: ["pseudonym"],
  name: "pi_pseudonym",
  unique: true,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

db._collection(transRelationshipColName).ensureIndex({
  type: "persistent",
  fields: ["EndToEndId"],
  name: "pi_EndToEndId",
  unique: false, //for pacs002/pacs008 separate records
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

/*** TRANSACTION HISTORY ***/
// TransactionHistory DB
const transactionHistoryDbName = "transactionHistory";
// TransactionHistory Collections
const transactionHistoryPacs002ColName = "transactionHistoryPacs002";
const transactionHistoryPacs008ColName = "transactionHistoryPacs008";
const transactionHistoryPain001ColName = "transactionHistoryPain001";
const transactionHistoryPain013ColName = "transactionHistoryPain013";

// TransactionHistory Setup
db._useDatabase(systemDb);
db._createDatabase(transactionHistoryDbName);
db._useDatabase(transactionHistoryDbName);
db._create(transactionHistoryPacs002ColName);
db._create(transactionHistoryPacs008ColName);
db._create(transactionHistoryPain001ColName);
db._create(transactionHistoryPain013ColName);

// TransactionHistory Indices
// Pacs002
db._collection(transactionHistoryPacs002ColName).ensureIndex({
  type: "persistent",
  fields: ["FIToFIPmtSts.TxInfAndSts.OrgnlEndToEndId"],
  name: "pi_EndToEndId",
  unique: true,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

// Pacs008
db._collection(transactionHistoryPacs008ColName).ensureIndex({
  type: "persistent",
  fields: ["FIToFICstmrCdtTrf.CdtTrfTxInf.Dbtr.Id.PrvtId.Othr.Id"],
  name: "pi_DebtorAcctId",
  unique: false,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

db._collection(transactionHistoryPacs008ColName).ensureIndex({
  type: "persistent",
  fields: ["FIToFICstmrCdtTrf.CdtTrfTxInf.Cdtr.Id.PrvtId.Othr.Id"],
  name: "pi_CreditorAcctId",
  unique: false,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

db._collection(transactionHistoryPacs008ColName).ensureIndex({
  type: "persistent",
  fields: ["FIToFICstmrCdtTrf.GrpHdr.CreDtTm"],
  name: "pi_CreDtTm",
  unique: false,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

db._collection(transactionHistoryPacs008ColName).ensureIndex({
  type: "persistent",
  fields: ["FIToFICstmrCdtTrf.CdtTrfTxInf.PmtId.EndToEndId"],
  name: "pi_EndToEndId",
  unique: true,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

// Pain001
db._collection(transactionHistoryPain001ColName).ensureIndex({
  type: "persistent",
  fields: ["CstmrCdtTrfInitn.PmtInf.CdtTrfTxInf.PmtId.EndToEndId"],
  name: "pi_EndToEndId",
  unique: true,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

db._collection(transactionHistoryPain001ColName).ensureIndex({
  type: "persistent",
  fields: ["CstmrCdtTrfInitn.PmtInf.DbtrAcct.Id.Othr.Id"],
  name: "pi_DebtorAcctId",
  unique: false,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

db._collection(transactionHistoryPain001ColName).ensureIndex({
  type: "persistent",
  fields: ["CstmrCdtTrfInitn.PmtInf.CdtTrfTxInf.CdtrAcct.Id.Othr.Id"],
  name: "pi_CreditorAcctId",
  unique: false,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

db._collection(transactionHistoryPain001ColName).ensureIndex({
  type: "persistent",
  fields: ["CstmrCdtTrfInitn.GrpHdr.CreDtTm"],
  name: "pi_CreDtTm",
  unique: false,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

db._collection(transactionHistoryPain001ColName).ensureIndex({
  type: "persistent",
  fields: ["CstmrCdtTrfInitn.PmtInf.CdtTrfTxInf.PmtId.EndToEndId"],
  name: "pi_PmtId-EndToEndId",
  unique: true,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});

// Pain013
db._collection(transactionHistoryPain013ColName).ensureIndex({
  type: "persistent",
  fields: ["CdtrPmtActvtnReq.PmtInf.CdtTrfTxInf.PmtId.EndToEndId"],
  name: "pi_EndToEndId",
  unique: true,
  sparse: false,
  deduplicate: false,
  estimates: true,
  cacheEnabled: true,
  inBackground: false,
});
