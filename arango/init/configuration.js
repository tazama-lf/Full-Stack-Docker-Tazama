const db = require("@arangodb").db;

const systemDb = "_system";

let configData = [
  {
    _key: "901",
    _id: "configuration/901",
    id: "901@1.0.0",
    cfg: "1.0.0",
    desc: "Amount of transactions debtor made",
    config: {
      exitConditions: [
        {
          subRuleRef: ".x00",
          outcome: false,
          reason: "Unsuccessful transaction",
        },
      ],
      timeframes: [
        {
          threshold: 86400000,
        },
      ],
      bands: [
        {
          subRuleRef: ".01",
          upperLimit: 2,
          outcome: true,
          reason: "Debtor made less than two transactions",
        },
        {
          subRuleRef: ".02",
          lowerLimit: 2,
          upperLimit: 3,
          outcome: true,
          reason: "Debtor made three transactions",
        },
        {
          subRuleRef: ".03",
          lowerLimit: 3,
          outcome: false,
          reason: "Debtor made four or more transactions",
        },
      ],
    },
  },
];

let typologyExpData = [
  {
    _key: "901",
    _id: "typologyExpression/901",
    typology_name: "test typology for rule 901",
    id: "001@1.0.0",
    cfg: "1.0.0",
    workflow: {
      alertThreshold: 50,
    },
    rules: [
      {
        id: "901@1.0.0",
        cfg: "1.0.0",
        ref: ".01",
        true: "100",
        false: "0",
      },
    ],
    expression: {
      operator: "+",
      terms: [
        {
          id: "901@1.0.0",
          cfg: "1.0.0",
        },
      ],
    },
  },
];

let transactionData = [
  {
    id: "004@1.0.0",
    cfg: "1.0.0",
    txTp: "pacs.002.001.12",
    channels: [
      {
        id: "001@1.0.0",
        cfg: "1.0.0",
        typologies: [
          {
            id: "001@1.0.0",
            cfg: "1.0.0",
          },
        ],
      },
    ],
  },
];

// Config DB
const configDbName = "Configuration";
// Config Collections
const configColName = "configuration";
const typologyColName = "typologyExpression";
const transactionColName = "transactionConfiguration";

// Config Setup
db._useDatabase(systemDb);

db._createDatabase(configDbName);
db._useDatabase(configDbName);

db._create(configColName);
db._create(typologyColName);
db._create(transactionColName);

// Indexes
// None

// Populate
db._collection(configColName).save(configData);
db._collection(typologyColName).save(typologyExpData);
db._collection(transactionColName).save(transactionData);
