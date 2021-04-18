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

def main():
    listOfBatches = []

    try:
        df = AzurePackage("SelectAllData", "[shapes]")
        coordinateDF = df[["shape_id", "shape_pt_lat","shape_pt_lon"]]
        request = coordinateDF.drop_duplicates(subset=None, 
                                            keep='first', 
                                            inplace=False)
        coordinatesReq = Url("generateLocationRequest", request)
        for key, value in coordinatesReq.items():
            if key == "locations":
                locations = value
        for each in value:
            batches = {"locations" : []}
            requestSize = 0
            while dictsize(batches["locations"]) +\
                                dictsize(each) + \
                                dictsize(batches) < 1024:
                location = value.pop(0)
                batches["locations"].append(location)
            listOfBatches.append(batches)
        for each in listOfBatches:
            if dictsize(each) > 1024:
                raise Exception(in_config.RequestToBig)
            else:
                pass
        for each in listOfBatches:
            shapeData = Url("mineElevationData",each)
            print(shapeData)
            time.sleep(10)

    except pd.io.sql.DatabaseError as e:
        print(in_config.NoSQLShema)

    except urllib.request.HTTPError as e:
        if e.code == "403":
            print(in_config.SQLConnectionFail)
        
    except Exception as e:
        print(in_config.UNKMGO)
        print(e)
        
if __name__ == "__main__":
    main()