import sys
import os
sys.path.append(os.environ.get("PYTHONPATH"))

import createNewData.data.config as in_config
from createNewData.pypackages.Azure import Azure

AzurePackage = Azure(in_config)

shapeIds = AzurePackage("SelectDistinct",
                              "shape_id",
                              "[dbo].[shapes]")
import sys
import os
import time
import pymongo
import urllib
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

for each in shapeIds.iterrows():
    shapeData = {}
    try:
        # Generate the Pandas table of all the Longtitudes and Latitudes
        # for each shape
        elevations = AzurePackage("SelectLongLat",
                                "[shape_id],[shape_pt_lat],[shape_pt_lon]",
                                "[dbo].[shapes]",
                                "[shape_id]",
                                each[1][0])

        # Generate the Json document for upload to MongoDB
        shapeData[each[1][0].replace(".","_")] = Url("mineElevationData",elevations)
    except urllib.error.HTTPError as e:
        print("Please ensure that the URL in the config file is not out of date.")
        print(e)
    try:
        # Upload the Json document to MongoDB
        if not shapeData:
            AzurePackage("UploadToMongo","shapes",shapeData)
        else:
            raise Exception("No data present in the current dataframe.")
    except TypeError as e:
        print("Type error in cosmos connection string, please check your environment variables")
    except pymongo.errors.DuplicateKeyError as e:
        print("File already exists for this key in the database.")
    except Exception as e:
        print("An unknown exception occured while attempting to upload to mongodb.")

    print("%s seconds" % (time.time() - start_time))
print("%s seconds" % (time.time() - start_time))

