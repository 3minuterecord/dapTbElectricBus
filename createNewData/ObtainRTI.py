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

try:
    import createNewData.data.config as in_config
    from createNewData.pypackages.Azure import Azure
    from createNewData.pypackages.urlHandler import UrlHandler
    AzurePackage = Azure(in_config)
    Url = UrlHandler(in_config)
    
    
except ImportError as e:
    print(in_config.FailedImport)
    print(e)
while True:
    url = in_config.url2
    headers = in_config.RTIheaders
    response = Url("callURL", url, {}, headers)
    JsonData = response.read().decode('utf8').replace("'", '"')
    RTIgtfs = json.loads(JsonData)
    # try:
        # AzurePackage("DropMongoColl","RTIgtfs")
    AzurePackage("UploadToMongo","RTIgtfs",RTIgtfs)
    print("uploaded")
    time.sleep(60)
    # except pymongo.errors.WriteError as e:
    #     print("An error occured while attempting to write the GTFS data to Mongo Database.")
    #     print(type(e))
    # except urllib.HTTPError as e:
    #     print("An error occured while attempting to connect to the Mongo Database.")
    #     print(type(e))
    # time.sleep(60)
