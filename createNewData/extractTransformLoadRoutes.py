# Extract Raw Route Data from Cosmos DB & Write to Azure SQL
# ==========================================================
print('hello')
import json

filepath = 'C:\MyApps\dapTbElectricDublinBus\keys.json'
with open(filepath) as json_file:
    key_data = json.load(json_file)
    cosmos_key = key_data['cosmos_key']  
    print(cosmos_key)

#%%    
# Extract Data Raw Data from Azure Cosmos DB for MongoDB API
# ==========================================================
# Azure Cosmos DB service implements wire protocols for common NoSQL APIs including Cassandra, MongoDB. 
# This allows you to use your familiar NoSQL client drivers and tools to interact with your Cosmos database.
from pymongo import MongoClient
uri = "mongodb://electric-bus-cosmos-east-us:" + cosmos_key + "@electric-bus-cosmos-east-us.mongo.cosmos.azure.com:10255/?ssl=true&retrywrites=false&replicaSet=globaldb&maxIdleTimeMS=120000&appName=@electric-bus-cosmos-east-us@"
client = MongoClient(uri)

# Create database
import pprint

# Database details
db = client['bus_routes_nosql']

# Collection for route data
routes = db.routes

# Extract data
pprint.pprint(routes.find_one())
