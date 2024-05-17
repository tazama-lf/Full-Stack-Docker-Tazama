const db = require("@arangodb").db;

const networkMapData = [{
  active: true,
  name: "FullNatsNoTP000",
  cfg: "1.0.0",
  messages: [
    {
      id: "004@1.0.0",
      cfg: "1.0.0",
      txTp: "pacs.002.001.12",
      typologies: [
        {
          id: "typology-processor@1.0.0",
          cfg: "999@1.0.0",
          rules: [
            {
              id: "901@1.0.0",
              cfg: "1.0.0",
            }
          ],
        }
      ],
    },
  ],
}];

const systemDb = "_system";
// NetworkMap DB
const networkDbName = "networkmap";
// NetworkMap Collections
const networkColName = "networkConfiguration";

// NetworkMap Setup
db._useDatabase(systemDb);

db._createDatabase(networkDbName);
db._useDatabase(networkDbName);

db._create(networkColName);

db._collection(networkColName).save(networkMapData);

// Indexes
// None

