// SPDX-License-Identifier: Apache-2.0

const db = require("@arangodb").db;

const systemDb = "_system";
// Pseudonyms DB
const pseudonymsDbName = "pseudonyms";
// Pseudonyms Collections
const pseudonymsColName = "pseudonyms";
const accountHolderColName = "account_holder";
const accountsColName = "accounts";
const entitiesColName = "entities";
const transRelationshipColName = "transactionRelationship";

// Pseudonyms Setup
db._useDatabase(systemDb);

db._createDatabase(pseudonymsDbName);
db._useDatabase(pseudonymsDbName);

db._create(pseudonymsColName);
db._createEdgeCollection(accountHolderColName);
db._create(accountsColName);
db._create(entitiesColName);
db._createEdgeCollection(transRelationshipColName);

// Indexes
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