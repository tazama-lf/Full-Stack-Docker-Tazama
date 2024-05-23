// SPDX-License-Identifier: Apache-2.0

const db = require("@arangodb").db;

const systemDb = "_system";
// TransactionHistory DB
const transactionHistoryDbName = "transactionHistory";
// TransactionHistory Collections
const transactionHistoryPacs002ColName = "transactionHistoryPacs002";
const transactionHistoryPacs008ColName = "transactionHistoryPacs008";
const transactionHistoryPain001ColName = "transactionHistoryPain001";
const transactionHistoryPain013ColName = "transactionHistoryPain013";
// const transactionsColName = "transactions";

// TransactionHistory Setup
db._useDatabase(systemDb);

db._createDatabase(transactionHistoryDbName);
db._useDatabase(transactionHistoryDbName);

db._create(transactionHistoryPacs002ColName);
db._create(transactionHistoryPacs008ColName);
db._create(transactionHistoryPain001ColName);
db._create(transactionHistoryPain013ColName);
// db._create(transactionsColName);

// Indexes
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
  fields: ["FIToFICstmrCdt.CdtTrfTxInf.Dbtr.Id.PrvtId.Othr.Id"],
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
  fields: ["FIToFICstmrCdt.CdtTrfTxInf.Cdtr.Id.PrvtId.Othr.Id"],
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
  fields: ["FIToFICstmrCdt.GrpHdr.CreDtTm"],
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
  fields: ["FIToFICstmrCdt.CdtTrfTxInf.PmtId.EndToEndId"],
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
