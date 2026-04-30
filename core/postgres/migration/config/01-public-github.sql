\connect configuration;

insert into
    network_map (configuration)
values (
        '{
  "active": true,
  "name": "Public Network Map",
  "cfg": "1.0.0",
  "tenantId": "DEFAULT",
  "creDtTm": "2026-04-08T00:00:00.000Z",
  "updDtTm": "2026-04-08T00:00:00.000Z",
  "messages": [
    {
      "id": "004@1.0.0",
      "cfg": "1.0.0",
      "txTp": "pacs.002.001.12",
      "typologies": [
        {
          "id": "typology-processor@1.0.0",
          "cfg": "999-901@1.0.0",
          "tenantId": "DEFAULT",
          "rules": [
            {
              "id": "EFRuP@1.0.0",
              "cfg": "none"
            },
            {
              "id": "901@1.0.0",
              "cfg": "1.0.0"
            }
          ]
        }
      ]
    }
  ]
}'
    );