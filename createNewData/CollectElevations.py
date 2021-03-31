import sys
import os
sys.path.append(os.environ.get("PYTHONPATH"))

import createNewData.data.config as in_config
from createNewData.pypackages.Azure import Azure

AzurePackage = Azure(in_config)

SqlDataCursor = AzurePackage("SelectDistinct",
                              "shape_id",
                              "[dbo].[shapes]")
print(SqlDataCursor)
