const ruleConfigData = [
  {
    _key: "tenant-001@901@1.0.0@1.0.0",
    _id: "tenant-001@901@1.0.0@1.0.0",
    tenantId: "tenant-001",
    id: "901@1.0.0",
    cfg: "1.0.0",
    desc: "Number of outgoing transactions - debtor",
    config: {
      parameters: {
        maxQueryRange: 86400000,
      },
      exitConditions: [
        {
          subRuleRef: ".x00",
          reason: "Incoming transaction is unsuccessful",
        },
      ],
      bands: [
        {
          subRuleRef: ".01",
          upperLimit: 2,
          reason: "The debtor has performed one transaction to date",
        },
        {
          subRuleRef: ".02",
          lowerLimit: 2,
          upperLimit: 3,
          reason: "The debtor has performed two transactions to date",
        },
        {
          subRuleRef: ".03",
          lowerLimit: 3,
          reason: "The debtor has performed three or more transactions to date",
        },
      ],
    },
  },
  {
    _key: "tenant-002@901@1.0.0@1.0.0",
    _id: "tenant-002@901@1.0.0@1.0.0",
    tenantId: "tenant-002",
    id: "901@1.0.0",
    cfg: "1.0.0",
    desc: "Number of outgoing transactions - debtor",
    config: {
      parameters: {
        maxQueryRange: 86400000,
      },
      exitConditions: [
        {
          subRuleRef: ".x00",
          reason: "Incoming transaction is unsuccessful",
        },
      ],
      bands: [
        {
          subRuleRef: ".01",
          upperLimit: 2,
          reason: "The debtor has performed one transaction to date",
        },
        {
          subRuleRef: ".02",
          lowerLimit: 2,
          upperLimit: 3,
          reason: "The debtor has performed two transactions to date",
        },
        {
          subRuleRef: ".03",
          lowerLimit: 3,
          reason: "The debtor has performed three or more transactions to date",
        },
      ],
    },
  },
];

const typologyConfigData = [
  {
    _key: "tenant-001@typology-999@1.0.0@999@1.0.0",
    _id: "tenant-001@typology-999@1.0.0@999@1.0.0",
    tenantId: "tenant-001",
    desc: "Rule-901-Typology-999-Tenant-001",
    id: "typology-processor@1.0.0",
    cfg: "999@1.0.0",
    workflow: {
      alertThreshold: 200,
      interdictionThreshold: 400,
      flowProcessor: "EFRuP@1.0.0",
    },
    rules: [
      {
        id: "901@1.0.0",
        cfg: "1.0.0",
        termId: "v901at100at100",
        wghts: [
          {
            ref: ".err",
            wght: "0",
          },
          {
            ref: ".x00",
            wght: "100",
          },
          {
            ref: ".01",
            wght: "100",
          },
          {
            ref: ".02",
            wght: "200",
          },
          {
            ref: ".03",
            wght: "400",
          },
        ],
      },
      {
        id: "EFRuP@1.0.0",
        cfg: "none",
        termId: "vEFRuPat100atnone",
        wghts: [
          {
            ref: ".err",
            wght: "0",
          },
          {
            ref: "override",
            wght: "0",
          },
          {
            ref: "non-overridable-block",
            wght: "0",
          },
          {
            ref: "overridable-block",
            wght: "0",
          },
          {
            ref: "none",
            wght: "0",
          },
        ],
      },
    ],
    expression: ["Add", "v901at100at100"],
  },
  {
    _key: "tenant-002@typology-999@1.0.0@999@1.0.0",
    _id: "tenant-002@typology-999@1.0.0@999@1.0.0",
    tenantId: "tenant-002",
    desc: "Rule-901-Typology-999-Tenant-002",
    id: "typology-processor@1.0.0",
    cfg: "999@1.0.0",
    workflow: {
      alertThreshold: 200,
      interdictionThreshold: 400,
      flowProcessor: "EFRuP@1.0.0",
    },
    rules: [
      {
        id: "901@1.0.0",
        cfg: "1.0.0",
        termId: "v901at100at100",
        wghts: [
          {
            ref: ".err",
            wght: "0",
          },
          {
            ref: ".x00",
            wght: "100",
          },
          {
            ref: ".01",
            wght: "100",
          },
          {
            ref: ".02",
            wght: "200",
          },
          {
            ref: ".03",
            wght: "400",
          },
        ],
      },
      {
        id: "EFRuP@1.0.0",
        cfg: "none",
        termId: "vEFRuPat100atnone",
        wghts: [
          {
            ref: ".err",
            wght: "0",
          },
          {
            ref: "override",
            wght: "0",
          },
          {
            ref: "non-overridable-block",
            wght: "0",
          },
          {
            ref: "overridable-block",
            wght: "0",
          },
          {
            ref: "none",
            wght: "0",
          },
        ],
      },
    ],
    expression: ["Add", "v901at100at100"],
  },
];

const networkConfigData = [
  {
    active: true,
    tenantId: "tenant-001",
    cfg: "1.0.0",
    messages: [
      {
        id: "004@1.0.0",
        cfg: "1.0.0",
        txTp: "pacs.002.001.12",
        typologies: [
          {
            id: "typology-processor@1.0.0",
            tenantId: "tenant-001",
            cfg: "999@1.0.0",
            rules: [
              {
                id: "EFRuP@1.0.0",
                cfg: "none",
              },
              {
                id: "901@1.0.0",
                cfg: "1.0.0",
              },
            ],
          },
        ],
      },
    ],
  },
  {
    active: true,
    tenantId: "tenant-002",
    cfg: "1.0.0",
    messages: [
      {
        id: "004@1.0.0",
        cfg: "1.0.0",
        txTp: "pacs.002.001.12",
        typologies: [
          {
            id: "typology-processor@1.0.0",
            tenantId: "tenant-002",
            cfg: "999@1.0.0",
            rules: [
              {
                id: "EFRuP@1.0.0",
                cfg: "none",
              },
              {
                id: "901@1.0.0",
                cfg: "1.0.0",
              },
            ],
          },
        ],
      },
    ],
  },
];

const configDbName = "configuration";
const ruleConfigColName = "ruleConfiguration";
const typologyConfigColName = "typologyConfiguration";
const networkConfigColName = "networkConfiguration";

db._useDatabase(configDbName);
db._collection(ruleConfigColName).save(ruleConfigData);
db._collection(typologyConfigColName).save(typologyConfigData);
db._collection(networkConfigColName).save(networkConfigData);
