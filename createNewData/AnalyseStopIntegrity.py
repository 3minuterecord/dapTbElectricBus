import sys
from sys import getsizeof as dictsize
import os
import json
import time
import pymongo
import urllib
import pandas as pd
import numpy as np
import urllib
import urllib.request
import missingno as msno

try:
    import createNewData.data.config as in_config
    from createNewData.pypackages.Azure import Azure
    from createNewData.pypackages.urlHandler import UrlHandler
    AzurePackage = Azure(in_config)
    Url = UrlHandler(in_config)
    
    
except ImportError as e:
    print(in_config.FailedImport)
    print(e)

conn = AzurePackage("AzureDBConn", in_config.teamConnQuote)
SQLString = """Select * FROM [distances]"""
distancedf = pd.read_sql(SQLString, conn)
conn.close()

conn = AzurePackage("AzureDBConn", in_config.teamConnQuote)
SQLString = """Select distances.*, stopEelevations.elevation, stops.stop_id
               FROM distances, stops, stopEelevations
               WHERE distances.stop = stops.stop_id
               AND stops.stop_lat = stopEelevations.latitude AND stops.stop_lon = stopEelevations.longitude
               """
elevationdf = pd.read_sql(SQLString, conn)
conn.close()

merged = elevationdf[["stop"]].drop_duplicates()
distances = distancedf[["stop"]].drop_duplicates()

if len(distances) == len(merged):
    print("No elevations missing from the merged data.")
else:
    mergedTest = pd.merge(distances, merged, how='outer', indicator='Exist')

mergedTest = mergedTest.replace("left_only", np.nan)
print(msno.matrix(mergedTest))