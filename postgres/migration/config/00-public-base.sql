\connect configuration;

insert into
    rule (configuration)
values (
        '{
  "id": "901@1.0.0",
  "cfg": "1.0.0",
  "tenantId": "DEFAULT",
  "desc": "Number of outgoing transactions - debtor",
  "config": {
    "parameters": {
      "maxQueryRange": 86400000
    },
    "exitConditions": [
      {
        "subRuleRef": ".x00",
        "reason": "Incoming transaction is unsuccessful"
      }
    ],
    "bands": [
      {
        "subRuleRef": ".01",
        "upperLimit": 2,
        "reason": "The debtor has performed one transaction to date"
      },
      {
        "subRuleRef": ".02",
        "lowerLimit": 2,
        "upperLimit": 3,
        "reason": "The debtor has performed two transactions to date"
      },
      {
        "subRuleRef": ".03",
        "lowerLimit": 3,
        "reason": "The debtor has performed three or more transactions to date"
      }
    ]
  }
}'
    ), (
        '{
  "id": "902@1.0.0",
  "cfg": "1.0.0",
  "tenantId": "DEFAULT",
  "desc": "Number of incoming transactions - creditor",
  "config": {
    "parameters": {
      "maxQueryRange": 86400000
    },
    "exitConditions": [
      {
        "subRuleRef": ".x00",
        "reason": "Incoming transaction is unsuccessful"
      }
    ],
    "bands": [
      {
        "subRuleRef": ".01",
        "upperLimit": 2,
        "reason": "The creditor has received one transaction to date"
      },
      {
        "subRuleRef": ".02",
        "lowerLimit": 2,
        "upperLimit": 3,
        "reason": "The creditor has received two transactions to date"
      },
      {
        "subRuleRef": ".03",
        "lowerLimit": 3,
        "reason": "The creditor has received three or more transactions to date"
      }
    ]
  }
}'
    );

insert into
    typology (configuration)
values (
        '{
  "typology_name": "Typology-999-Rule-901",
  "id": "typology-processor@1.0.0",
  "cfg": "999-901@1.0.0",
  "tenantId": "DEFAULT",
  "workflow": {
    "alertThreshold": 200,
    "interdictionThreshold": 400,
    "flowProcessor": "EFRuP@1.0.0"
  },
  "rules": [
    {
      "id": "901@1.0.0",
      "cfg": "1.0.0",
      "termId": "v901at100at100",
      "wghts": [
        {
          "ref": ".err",
          "wght": "0"
        },
        {
          "ref": ".x00",
          "wght": "100"
        },
        {
          "ref": ".01",
          "wght": "100"
        },
        {
          "ref": ".02",
          "wght": "200"
        },
        {
          "ref": ".03",
          "wght": "400"
        }
      ]
    },
    {
      "id": "EFRuP@1.0.0",
      "cfg": "none",
      "termId": "vEFRuPat100atnone",
      "wghts": [
        {
          "ref": ".err",
          "wght": "0"
        },
        {
          "ref": "override",
          "wght": "0"
        },
        {
          "ref": "non-overridable-block",
          "wght": "0"
        },
        {
          "ref": "overridable-block",
          "wght": "0"
        },
        {
          "ref": "none",
          "wght": "0"
        }
      ]
    }
  ],
  "expression": ["Add", "v901at100at100"]
}'
    ), (
        '{
  "typology_name": "Typology-999-Rule-901-and-902",
  "id": "typology-processor@1.0.0",
  "cfg": "999@1.0.0",
  "tenantId": "DEFAULT",
  "workflow": {
    "alertThreshold": 300,
    "interdictionThreshold": 500,
    "flowProcessor": "EFRuP@1.0.0"
  },
  "rules": [
    {
      "id": "901@1.0.0",
      "cfg": "1.0.0",
      "termId": "v901at100at100",
      "wghts": [
        {
          "ref": ".err",
          "wght": "0"
        },
        {
          "ref": ".x00",
          "wght": "100"
        },
        {
          "ref": ".01",
          "wght": "100"
        },
        {
          "ref": ".02",
          "wght": "200"
        },
        {
          "ref": ".03",
          "wght": "400"
        }
      ]
    },
    {
      "id": "902@1.0.0",
      "cfg": "1.0.0",
      "termId": "v902at100at100",
      "wghts": [
        {
          "ref": ".err",
          "wght": "0"
        },
        {
          "ref": ".x00",
          "wght": "100"
        },
        {
          "ref": ".01",
          "wght": "100"
        },
        {
          "ref": ".02",
          "wght": "200"
        },
        {
          "ref": ".03",
          "wght": "400"
        }
      ]
    },
    {
      "id": "EFRuP@1.0.0",
      "cfg": "none",
      "termId": "vEFRuPat100atnone",
      "wghts": [
        {
          "ref": ".err",
          "wght": "0"
        },
        {
          "ref": "override",
          "wght": "0"
        },
        {
          "ref": "non-overridable-block",
          "wght": "0"
        },
        {
          "ref": "overridable-block",
          "wght": "0"
        },
        {
          "ref": "none",
          "wght": "0"
        }
      ]
    }
  ],
  "expression": ["Add", "v901at100at100", "v902at100at100"]
}'
    );