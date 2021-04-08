import sys
import os
import time
import pymongo
import urllib
import pandas as pd
start_time = time.time()
sys.path.append(os.environ.get("PYTHONPATH"))

try:
    import createNewData.data.config as in_config
    from createNewData.pypackages.Azure import Azure
    AzurePackage = Azure(in_config)
    
except ImportError as e:
    print("Failed to import critical modules for this script.")
    print("Please confirm that files exist in the correct locations.")
    print(e)

listOfObjects = []
listOfElevations = []

dbcollections = AzurePackage("SelectFromMongo")
for collection in dbcollections.find():
    for each in collection:
        if type(collection[each]) is dict:
            listOfObjects.append(collection[each])

for each in listOfObjects:
    for key, value in each.items():
        for elevation in value:
            listOfElevations.append(elevation)

df = pd.DataFrame(listOfElevations)



dfTrimmed = df.drop_duplicates()

import sys
import os
sys.path.append(os.environ.get("PYTHONPATH"))

import createNewData.data.config as in_config
from createNewData.pypackages.Azure import Azure

AzurePackage = Azure(in_config)

df = pd.read_csv(in_config.shapes)

SqlDataCursor = AzurePackage("UploadToSQL",
                              dfTrimmed,
                              "elevations")