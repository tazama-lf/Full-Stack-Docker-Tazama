// SPDX-License-Identifier: Apache-2.0

const systemDb = "_system";
// Evaluations Results DB
const evaluationsDbName = "evaluationResults";
// Transactions Collections
const transactionsColName = "transactions";

// Transactions Setup
db._useDatabase(systemDb);

db._createDatabase(evaluationsDbName);
db._useDatabase(evaluationsDbName);

db._create(transactionsColName);

// Indexes
// None
