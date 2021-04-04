import sys
import os
sys.path.append(os.environ.get("PYTHONPATH"))

import createNewData.data.config as in_config
from createNewData.pypackages.Azure import Azure
from createNewData.pypackages.urlHandler import UrlHandler

AzurePackage = Azure(in_config)
Url = UrlHandler(in_config)

shapeData = AzurePackage("SelectLongLat",
                         "[shape_id],[shape_pt_lat],[shape_pt_lon]",
                         "[dbo].[shapes]",
                         "[shape_id]",
                         "60-1-b12-1.1.O")
a = Url("mineElevationData",shapeData)
print(a)