\connect configuration;

insert into
    rule (configuration)
values (
        '{
  "id": "901@4.0.0",
  "cfg": "4.0.0",
  "tenantId": "DEFAULT",
  "creDtTm": "2026-07-20T00:00:00.000Z",
  "updDtTm": "2026-07-20T00:00:00.000Z",
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
        "reason": "The debtor has performed one transaction in the last day"
      },
      {
        "subRuleRef": ".02",
        "lowerLimit": 2,
        "upperLimit": 3,
        "reason": "The debtor has performed two transactions in the last day"
      },
      {
        "subRuleRef": ".03",
        "lowerLimit": 3,
        "reason": "The debtor has performed three or more transactions in the last day"
      }
    ]
  }
}'
    ), (
        '{
  "id": "902@4.0.0",
  "cfg": "4.0.0",
  "tenantId": "DEFAULT",
  "creDtTm": "2026-07-20T00:00:00.000Z",
  "updDtTm": "2026-07-20T00:00:00.000Z",
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
        "reason": "The creditor has received one transaction in the last day"
      },
      {
        "subRuleRef": ".02",
        "lowerLimit": 2,
        "upperLimit": 3,
        "reason": "The creditor has received two transactions in the last day"
      },
      {
        "subRuleRef": ".03",
        "lowerLimit": 3,
        "reason": "The creditor has received three or more transactions in the last day"
      }
    ]
  }
}'
    ), (
      '{
  "id": "EFRuP@4.0.0",
  "cfg": "none",
  "tenantId": "DEFAULT",
  "creDtTm": "2026-07-20T00:00:00.000Z",
  "updDtTm": "2026-07-20T00:00:00.000Z",
  "desc": "Event-Flow Rule Processor",
  "config": {
      "exitConditions": [
          {
              "subRuleRef": "none",
              "reason": "No entity or account condition in effect"
          },
          {
              "subRuleRef": "override",
              "reason": "An entity or account override condition is in effect"
          },
          {
              "subRuleRef": "block",
              "reason": "An entity or account block condition is in effect"
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
  "id": "typology-processor",
  "cfg": "999-901@4.0.0",
  "desc": "Typology for Rule 901",
  "tenantId": "DEFAULT",
  "creDtTm": "2026-07-20T00:00:00.000Z",
  "updDtTm": "2026-07-20T00:00:00.000Z",
  "workflow": {
    "alertThreshold": 200,
    "interdictionThreshold": 400,
    "flowProcessor": "EFRuP@4.0.0"
  },
  "rules": [
    {
      "id": "901@4.0.0",
      "cfg": "4.0.0",
      "termId": "v901at400at400",
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
      "id": "EFRuP@4.0.0",
      "cfg": "none",
      "termId": "vEFRuPat400atnone",
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
  "expression": ["Add", "v901at400at400"]
}'
    ), (
        '{
  "typology_name": "Typology-999-Rule-901-and-902",
  "id": "typology-processor",
  "cfg": "999-901-902@4.0.0",
  "desc": "Typology for Rule 901 and Rule 902",
  "tenantId": "DEFAULT",
  "creDtTm": "2026-07-20T00:00:00.000Z",
  "updDtTm": "2026-07-20T00:00:00.000Z",
  "workflow": {
    "alertThreshold": 300,
    "interdictionThreshold": 500,
    "flowProcessor": "EFRuP@4.0.0"
  },
  "rules": [
    {
      "id": "901@4.0.0",
      "cfg": "4.0.0",
      "termId": "v901at400at400",
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
      "id": "902@4.0.0",
      "cfg": "4.0.0",
      "termId": "v902at400at400",
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
      "id": "EFRuP@4.0.0",
      "cfg": "none",
      "termId": "vEFRuPat400atnone",
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
  "expression": ["Add", "v901at400at400", "v902at400at400"]
}'
    );