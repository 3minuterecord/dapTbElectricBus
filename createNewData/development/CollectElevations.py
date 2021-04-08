import sys
import os
import time
import pymongo
import urllib
import pandas as pd
import bson.objectid as id
start_time = time.time()
sys.path.append(os.environ.get("PYTHONPATH"))

try:
    import createNewData.data.config as in_config
    from createNewData.pypackages.Azure import Azure
    from createNewData.pypackages.urlHandler import UrlHandler
    AzurePackage = Azure(in_config)
    Url = UrlHandler(in_config)
    
except ImportError as e:
    print("Failed to import critical modules for this script.")
    print("Please confirm that files exist in the correct locations.")
    print(e)

listOfObjects = []
listOfElevations = []

dbcollections = AzurePackage("SelectFromMongo")
for each in dbcollections.find():
    for x in each:
        if type(each[x]) is not id.ObjectId:
            listOfObjects.append(each[x])

for each in listOfObjects:
    for key, value in each.items():
        for elevation in value:
            listOfElevations.append(elevation)

df = pd.DataFrame(listOfElevations)
print(df)
