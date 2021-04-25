import sys
import os
print(os.environ.get("PYTHONPATH"))
sys.path.append(os.environ.get("PYTHONPATH"))

import createNewData.data.config as in_config
from createNewData.pyPackages.Azure import Azure

SqlDataCursor = Azure(in_config).AzureDBConnect()

print(SqlDataCursor)
SqlDataCursor.close()