\connect configuration;

insert into
    network_map (configuration)
values (
        '{
  "active": true,
  "name": "Public Network Map",
  "cfg": "4.0.0",
  "tenantId": "DEFAULT",
  "creDtTm": "2026-07-20T00:00:00.000Z",
  "updDtTm": "2026-07-20T00:00:00.000Z",
  "messages": [
    {
      "id": "004@4.0.0",
      "cfg": "4.0.0",
      "txTp": "pacs.002.001.12",
      "typologies": [
        {
          "id": "typology-processor",
          "cfg": "999-901-902@4.0.0",
          "rules": [
            {
              "id": "EFRuP@4.0.0",
              "cfg": "none"
            },
            {
              "id": "901@4.0.0",
              "cfg": "4.0.0"
            },
            {
              "id": "902@4.0.0",
              "cfg": "4.0.0"
            }
          ]
        }
      ]
    }
  ]
}'
    );