\connect configuration;

insert into
    rule (configuration)
values (
        '{
    "id": "001@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Derived account age - creditor",
    "config": {
      "parameters": {},
      "exitConditions": [
        {
          "subRuleRef": ".x01",
          "reason": "No verifiable creditor account activity detected"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 86400000,
          "reason": "Creditor account is less than 1 day old"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 86400000,
          "reason": "Creditor account is more than 1 day old"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "002@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Transaction convergence - debtor",
    "config": {
      "parameters": {
        "maxQueryRange": 86400000
      },
      "exitConditions": [],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 5,
          "reason": "No transaction convergence detected on debtor account"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 5,
          "reason": "Transaction convergence detected on debtor account"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "003@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Account dormancy - creditor",
    "config": {
      "parameters": {},
      "exitConditions": [
        {
          "subRuleRef": ".x01",
          "reason": "No verifiable creditor account activity detected"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 7889229000,
          "reason": "Creditor account not dormant in the last 3 months"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 7889229000,
          "reason": "Creditor account dormant for more than 3 months"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "004@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Account dormancy - debtor",
    "config": {
      "parameters": {},
      "exitConditions": [
        {
          "subRuleRef": ".x01",
          "reason": "No verifiable debtor account activity detected"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 7889229000,
          "reason": "Debtor account not dormant in the last 3 months"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 7889229000,
          "reason": "Debtor account dormant for more than 12 months"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "006@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Outgoing transfer similarity - amounts",
    "config": {
      "parameters": {
        "maxQueryLimit": 3,
        "tolerance": 0.1
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Incoming transaction is unsuccessful"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 2,
          "reason": "No similar amounts detected in the most recent transactions from the debtor"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 2,
          "reason": "Two or more similar amounts detected in the most recent transactions from the debtor"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "007@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Outgoing transfer similarity - descriptions",
    "config": {
      "parameters": {},
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Unsuccessful transaction"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "lowerLimit": 0,
          "upperLimit": 1,
          "reason": "Identical descriptions for consecutive successful transactions"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 1,
          "upperLimit": 5,
          "reason": "Similar descriptions for consecutive successful transactions"
        },
        {
          "subRuleRef": ".03",
          "lowerLimit": 5,
          "reason": "Significantly different descriptions for consecutive successful transactions"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "008@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Outgoing transfer similarity - creditor",
    "config": {
      "parameters": {
        "maxQueryLimit": 3
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Unsuccessful transaction"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 2,
          "reason": "No recent transactions to the same creditor account"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 2,
          "reason": "Two or more recent transactions to the same creditor account"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "010@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Increased account activity: volume - debtor",
    "config": {
      "parameters": {
        "evaluationIntervalTime": 86400000
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Incoming transaction is unsuccessful"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        },
        {
          "subRuleRef": ".x03",
          "reason": "No variance in transaction history and the volume of recent incoming transactions shows an increase for the debtor"
        },
        {
          "subRuleRef": ".x04",
          "reason": "No variance in transaction history and the volume of recent incoming transactions is less than or equal to the historical average for the debtor"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 3,
          "reason": "The volume of recent outgoing transactions is within acceptable limits for the debtor"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 3,
          "reason": "The volume of recent outgoing transactions shows a significant increase for the debtor"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "011@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Increased account activity: volume - creditor",
    "config": {
      "parameters": {
        "evaluationIntervalTime": 86400000
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Incoming transaction is unsuccessful"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        },
        {
          "subRuleRef": ".x03",
          "reason": "No variance in transaction history and the volume of recent incoming transactions shows an increase for the creditor"
        },
        {
          "subRuleRef": ".x04",
          "reason": "No variance in transaction history and the volume of recent incoming transactions is less than or equal to the historical average for the creditor"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 3,
          "reason": "The volume of recent incoming transactions is within acceptable limits for the creditor"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 3,
          "reason": "The volume of recent incoming transactions shows a significant increase for the creditor"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "016@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Transaction convergence - creditor",
    "config": {
      "parameters": {
        "maxQueryRange": 86400000
      },
      "exitConditions": [],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 5,
          "reason": "No Transaction convergence detected on creditor account"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 5,
          "reason": "Transaction convergence detected on creditor account"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "017@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Transaction divergence - debtor",
    "config": {
      "parameters": {
        "maxQueryRange": 28800000
      },
      "exitConditions": [],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 5,
          "reason": "No Transaction divergence detected on source account"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 5,
          "reason": "Transaction divergence detected on source account"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "018@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Exceptionally large outgoing transfer - debtor",
    "config": {
      "parameters": {
        "maxQueryRange": 7889229000
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Incoming transaction is unsuccessful"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 1.5,
          "reason": "Outgoing transfer within historical limits"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 1.5,
          "reason": "Exceptionally large outgoing transfer detected"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "020@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Large transaction amount vs history - creditor",
    "config": {
      "parameters": {},
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Incoming transaction is unsuccessful"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        },
        {
          "subRuleRef": ".x03",
          "reason": "No variance in transaction history and the amount of the incoming transactions shows an increase for the creditor"
        },
        {
          "subRuleRef": ".x04",
          "reason": "No variance in transaction history and the amount of the incoming transactions is less than or equal to the historical average for the creditor"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 3,
          "reason": "The amount of the incoming transaction is within acceptable limits for the creditor"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 3,
          "reason": "The amount of the incoming transaction shows a significant increase for the creditor"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "021@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "A large number of similar transaction amounts - creditor",
    "config": {
      "parameters": {
        "maxQueryRange": 86400000,
        "tolerance": 0.1
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Unsuccessful transaction"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 5,
          "reason": "The creditor has received an insignificant number of transactions with the same amount in the last 24 hours"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 5,
          "reason": "The creditor has received a significant number of transactions with the same amount in the last 24 hours"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "024@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Non-commissioned transaction mirroring - creditor",
    "config": {
      "parameters": {
        "maxQueryRange": 86400000,
        "tolerance": 0.1
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Unsuccessful transaction"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        },
        {
          "subRuleRef": ".x03",
          "reason": "No non-commissioned transaction mirroring detected"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 2,
          "reason": "Immediate non-commissioned transaction mirroring detected"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 2,
          "reason": "Aggregated non-commissioned transaction mirroring detected"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "025@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Non-commissioned transaction mirroring - debtor",
    "config": {
      "parameters": {
        "maxQueryRange": 86400000,
        "tolerance": 0.1
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Unsuccessful transaction"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        },
        {
          "subRuleRef": ".x03",
          "reason": "No non-commissioned transaction mirroring detected"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 2,
          "reason": "Immediate non-commissioned transaction mirroring detected"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 2,
          "reason": "Aggregated non-commissioned transaction mirroring detected"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "026@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Commissioned transaction mirroring - creditor",
    "config": {
      "parameters": {
        "maxQueryRange": 86400000,
        "commission": 0.1,
        "tolerance": 0.1
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Unsuccessful transaction"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        },
        {
          "subRuleRef": ".x03",
          "reason": "No commissioned transaction mirroring detected"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 2,
          "reason": "Immediate commissioned transaction mirroring detected"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 2,
          "reason": "Aggregated commissioned transaction mirroring detected"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "027@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Commissioned transaction mirroring - debtor",
    "config": {
      "parameters": {
        "maxQueryRange": 86400000,
        "commission": 0.1,
        "tolerance": 0.1
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Unsuccessful transaction"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        },
        {
          "subRuleRef": ".x03",
          "reason": "No commissioned transaction mirroring detected"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 2,
          "reason": "Immediate commissioned transaction mirroring detected"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 2,
          "reason": "Aggregated commissioned transaction mirroring detected"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "028@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Age classification - debtor",
    "config": {
      "parameters": {},
      "exitConditions": [],
      "bands": [
        {
          "subRuleRef": ".01",
          "lowerLimit": 0,
          "upperLimit": 18,
          "reason": "The debtor is younger than 18 years old"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 18,
          "reason": "The debtor is 30 years or older"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "030@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Transfer to unfamiliar creditor account - debtor",
    "config": {
      "parameters": {},
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Unsuccessful transaction"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 2,
          "reason": "First successful payment from this debtor to creditor account"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 2,
          "reason": "Second or more successful payment from this debtor to creditor account"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "044@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Successful transactions from the debtor, including the new transaction",
    "config": {
      "parameters": {},
      "exitConditions": [],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 1,
          "reason": "To date, no successful payments have been made from debtor account"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 1,
          "upperLimit": 2,
          "reason": "To date, one successful payment has been made from debtor account"
        },
        {
          "subRuleRef": ".03",
          "lowerLimit": 2,
          "reason": "To date, two or more successful payments have been made from debtor account"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "045@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Successful transactions to the creditor, including the new transaction",
    "config": {
      "parameters": {},
      "exitConditions": [],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 1,
          "reason": "To date, no successful payments have been made to creditor account"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 1,
          "upperLimit": 2,
          "reason": "To date, one successful payment has been made to creditor account"
        },
        {
          "subRuleRef": ".03",
          "lowerLimit": 2,
          "reason": "To date, two or more successful payments have been made to creditor account"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "048@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Large transaction amount vs history - debtor",
    "config": {
      "parameters": {},
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Incoming transaction is unsuccessful"
        },
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        },
        {
          "subRuleRef": ".x03",
          "reason": "No variance in transaction history and the amount of the incoming transactions shows an increase for the debtor"
        },
        {
          "subRuleRef": ".x04",
          "reason": "No variance in transaction history and the amount of the incoming transactions is less than or equal to the historical average for the debtor"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 3,
          "reason": "The amount of the outgoing transaction is within acceptable limits for the debtor"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 3,
          "reason": "The amount of the outgoing transaction shows a significant increase for the debtor"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "054@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Synthetic data check - Benford''s Law - debtor",
    "config": {
      "parameters": {
        "minimumNumberOfTransactions": 50
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Incoming transaction is unsuccessful"
        },
        {
          "subRuleRef": ".x01",
          "reason": "At least 50 historical transactions required"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 15.507,
          "reason": "Benfords Law: Debtor transaction history indicates a low probability of fictitious amounts"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 15.507,
          "reason": "Benfords Law: Debtor transaction history indicates a high probability of fictitious amounts"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "063@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Synthetic data check - Benford''s Law - creditor",
    "config": {
      "parameters": {
        "minimumNumberOfTransactions": 50
      },
      "exitConditions": [
        {
          "subRuleRef": ".x00",
          "reason": "Incoming transaction is unsuccessful"
        },
        {
          "subRuleRef": ".x01",
          "reason": "At least 50 historical transactions required"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 15.507,
          "reason": "Benfords Law: Creditor transaction history indicates a low probability of fictitious amounts"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 15.507,
          "reason": "Benfords Law: Creditor transaction history indicates a high probability of fictitious amounts"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "074@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Distance over time from last transaction location - debtor",
    "config": {
      "parameters": {
        "maxQueryRange": 3600000
      },
      "exitConditions": [
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 50,
          "reason": "Reasonable walking speed"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 50,
          "reason": "Ludicrous speed"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "075@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Distance from habitual locations - debtor",
    "config": {
      "parameters": {
        "maxRadius": 5.0
      },
      "exitConditions": [
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 1,
          "reason": "The debtor has never transacted within 5km of this location"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 1,
          "upperLimit": 5,
          "reason": "The debtor has very few prior transactions within 5km of this location"
        },
        {
          "subRuleRef": ".03",
          "lowerLimit": 5,
          "reason": "The debtor frequently transacts near this location"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "076@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Time since last transaction - debtor",
    "config": {
      "parameters": {},
      "exitConditions": [
        {
          "subRuleRef": ".x01",
          "reason": "Insufficient transaction history"
        }
      ],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 300000,
          "reason": "Suspiciously quick follow-up transaction"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 300000,
          "reason": "Follow-up transaction speed within acceptable limits"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "078@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Transaction type",
    "config": {
      "parameters": {},
      "exitConditions": [],
      "cases": {
        "expressions": [
          {
            "subRuleRef": ".01",
            "value": "MP2B",
            "reason": "The transaction is identified as a Mobile P2B Payment"
          },
          {
            "subRuleRef": ".02",
            "value": "MP2P",
            "reason": "The transaction is identified as a Mobile P2P Payment"
          },
          {
            "subRuleRef": ".03",
            "value": "CASH",
            "reason": "The transaction is identified as a general cash management instruction"
          }
        ],
        "alternative": {
          "subRuleRef": ".00",
          "reason": "The transaction type is not defined in this rule configuration"
        }        
      }
    }
  }'
    ),
    (
        '{
    "id": "083@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Multiple accounts associated with a debtor",
    "config": {
      "parameters": {},
      "exitConditions": [],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 2,
          "reason": "Debtor has only one account"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 2,
          "reason": "Debtor has more one account"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "084@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Multiple accounts associated with a creditor",
    "config": {
      "parameters": {},
      "exitConditions": [],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 2,
          "reason": "Creditor has only one account"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 2,
          "reason": "Creditor has more one account"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "090@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Upstream transaction divergence - debtor",
    "config": {
      "parameters": {
        "maxQueryRangeUpstream": 86400000,
        "maxQueryRangeDownstream": 86400000
      },
      "exitConditions": [],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 3,
          "reason": "Upstream transaction divergence within acceptable limits"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 3,
          "reason": "Upstream transaction divergence detected"
        }
      ]
    }
  }'
    ),
    (
        '{
    "id": "091@1.0.0",
    "cfg": "1.0.0",
    "tenantId": "DEFAULT",
    "desc": "Transaction amount vs regulatory threshold",
    "config": {
      "parameters": {},
      "exitConditions": [],
      "bands": [
        {
          "subRuleRef": ".01",
          "upperLimit": 10000,
          "reason": "Transaction amount within regulatory limits"
        },
        {
          "subRuleRef": ".02",
          "lowerLimit": 10000,
          "reason": "Transaction amount exceeds regulatory threshold"
        }
      ]
    }
  }'
    );

insert into
    typology (configuration)
values (
        '
{
    "desc": "Complete rule coverage",
    "id": "typology-processor@1.0.0",
    "cfg": "000@1.0.0",
    "tenantId": "DEFAULT",
    "workflow": {
        "alertThreshold": 2200,
        "interdictionThreshold": 2600,
        "flowProcessor": "EFRuP@1.0.0"
    },
    "rules": [
        {
        "id": "001@1.0.0",
        "cfg": "1.0.0",
        "termId": "v001at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 100
            }
        ]
        },
        {
        "id": "002@1.0.0",
        "cfg": "1.0.0",
        "termId": "v002at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "003@1.0.0",
        "cfg": "1.0.0",
        "termId": "v003at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 100
            }
        ]
        },
        {
        "id": "004@1.0.0",
        "cfg": "1.0.0",
        "termId": "v004at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 100
            }
        ]
        },
        {
        "id": "006@1.0.0",
        "cfg": "1.0.0",
        "termId": "v006at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "007@1.0.0",
        "cfg": "1.0.0",
        "termId": "v007at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 400
            },
            {
            "ref": ".02",
            "wght": 200
            },
            {
            "ref": ".03",
            "wght": 0
            }
        ]
        },
        {
        "id": "008@1.0.0",
        "cfg": "1.0.0",
        "termId": "v008at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "010@1.0.0",
        "cfg": "1.0.0",
        "termId": "v010at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".x03",
            "wght": 100
            },
            {
            "ref": ".x04",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "011@1.0.0",
        "cfg": "1.0.0",
        "termId": "v011at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".x03",
            "wght": 100
            },
            {
            "ref": ".x04",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "016@1.0.0",
        "cfg": "1.0.0",
        "termId": "v016at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "017@1.0.0",
        "cfg": "1.0.0",
        "termId": "v017at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "018@1.0.0",
        "cfg": "1.0.0",
        "termId": "v018at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "020@1.0.0",
        "cfg": "1.0.0",
        "termId": "v020at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".x03",
            "wght": 100
            },
            {
            "ref": ".x04",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "021@1.0.0",
        "cfg": "1.0.0",
        "termId": "v021at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 100
            }
        ]
        },
        {
        "id": "024@1.0.0",
        "cfg": "1.0.0",
        "termId": "v024at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".x03",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 200
            },
            {
            "ref": ".02",
            "wght": 400
            }
        ]
        },
        {
        "id": "025@1.0.0",
        "cfg": "1.0.0",
        "termId": "v025at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".x03",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 200
            },
            {
            "ref": ".02",
            "wght": 400
            }
        ]
        },
        {
        "id": "026@1.0.0",
        "cfg": "1.0.0",
        "termId": "v026at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".x03",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 200
            },
            {
            "ref": ".02",
            "wght": 400
            }
        ]
        },
        {
        "id": "027@1.0.0",
        "cfg": "1.0.0",
        "termId": "v027at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".x03",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 200
            },
            {
            "ref": ".02",
            "wght": 400
            }
        ]
        },
        {
        "id": "028@1.0.0",
        "cfg": "1.0.0",
        "termId": "v028at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 100
            }
        ]
        },
        {
        "id": "030@1.0.0",
        "cfg": "1.0.0",
        "termId": "v030at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 200
            },
            {
            "ref": ".02",
            "wght": 100
            }
        ]
        },
        {
        "id": "044@1.0.0",
        "cfg": "1.0.0",
        "termId": "v044at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            },
            {
            "ref": ".03",
            "wght": 100
            }
        ]
        },
        {
        "id": "045@1.0.0",
        "cfg": "1.0.0",
        "termId": "v045at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            },
            {
            "ref": ".03",
            "wght": 100
            }
        ]
        },
        {
        "id": "048@1.0.0",
        "cfg": "1.0.0",
        "termId": "v048at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".x03",
            "wght": 100
            },
            {
            "ref": ".x04",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "054@1.0.0",
        "cfg": "1.0.0",
        "termId": "v054at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "063@1.0.0",
        "cfg": "1.0.0",
        "termId": "v063at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x00",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 200
            }
        ]
        },
        {
        "id": "074@1.0.0",
        "cfg": "1.0.0",
        "termId": "v074at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 100
            }
        ]
        },
        {
        "id": "075@1.0.0",
        "cfg": "1.0.0",
        "termId": "v075at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 200
            },
            {
            "ref": ".02",
            "wght": 100
            },
            {
            "ref": ".03",
            "wght": 0
            }
        ]
        },
        {
        "id": "076@1.0.0",
        "cfg": "1.0.0",
        "termId": "v076at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".x01",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 200
            },
            {
            "ref": ".02",
            "wght": 100
            }
        ]
        },
        {
        "id": "078@1.0.0",
        "cfg": "1.0.0",
        "termId": "v078at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".00",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 200
            },
            {
            "ref": ".02",
            "wght": 100
            },
            {
            "ref": ".03",
            "wght": 0
            }
        ]
        },
        {
        "id": "083@1.0.0",
        "cfg": "1.0.0",
        "termId": "v083at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 100
            }
        ]
        },
        {
        "id": "084@1.0.0",
        "cfg": "1.0.0",
        "termId": "v084at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 100
            }
        ]
        },
        {
        "id": "090@1.0.0",
        "cfg": "1.0.0",
        "termId": "v090at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 400
            }
        ]
        },
        {
        "id": "091@1.0.0",
        "cfg": "1.0.0",
        "termId": "v091at100at100",
        "wghts": [
            {
            "ref": ".err",
            "wght": 0
            },
            {
            "ref": ".01",
            "wght": 0
            },
            {
            "ref": ".02",
            "wght": 100
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
            "wght": 0
            },
            {
            "ref": "none",
            "wght": 0
            },
            {
            "ref": "override",
            "wght": 0
            },
            {
            "ref": "overridable-block",
            "wght": 0
            },
            {
            "ref": "non-overridable-block",
            "wght": 0
            }
        ]
        }
    ],
    "expression": [
        "Add",
        "v001at100at100",
        "v002at100at100",
        "v003at100at100",
        "v004at100at100",
        "v006at100at100",
        "v007at100at100",
        "v008at100at100",
        "v010at100at100",
        "v011at100at100",
        "v016at100at100",
        "v017at100at100",
        "v018at100at100",
        "v020at100at100",
        "v021at100at100",
        "v024at100at100",
        "v025at100at100",
        "v026at100at100",
        "v027at100at100",
        "v028at100at100",
        "v030at100at100",
        "v044at100at100",
        "v045at100at100",
        "v048at100at100",
        "v054at100at100",
        "v063at100at100",
        "v074at100at100",
        "v075at100at100",
        "v076at100at100",
        "v078at100at100",
        "v083at100at100",
        "v084at100at100",
        "v090at100at100",
        "v091at100at100"
    ]
}'
    );

insert into
    network_map (configuration)
values (
        '{
  "active": true,
  "cfg": "1.0.0",
  "tenantId": "DEFAULT",
  "messages": [
    {
      "id": "004@1.0.0",
      "cfg": "1.0.0",
      "txTp": "pacs.002.001.12",
      "typologies": [
        {
          "id": "typology-processor@1.0.0",
          "cfg": "000@1.0.0",
          "tenantId": "DEFAULT",
          "rules": [
            {
              "id": "001@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "002@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "003@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "004@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "006@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "007@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "008@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "010@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "011@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "016@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "017@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "018@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "020@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "021@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "024@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "025@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "026@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "027@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "028@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "030@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "044@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "045@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "048@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "054@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "063@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "074@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "075@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "076@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "078@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "083@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "084@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "090@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "091@1.0.0",
              "cfg": "1.0.0"
            },
            {
              "id": "EFRuP@1.0.0",
              "cfg": "none"
            }
          ]
        }
      ]
    }
  ]
}'
    );