import subprocess
import os
import pyodbc
import importlib.util

# Define the root folder where the repo has been downloaded to
root_folder = 'C:/MyApps'
folder_string = "/dapTbElectricDublinBus/_pipeline"
path = root_folder + folder_string

# Load common function file
spec = importlib.util.spec_from_file_location('functions', path + '/functions.py')
functs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(functs)
    
# Load Access Keys
# ================
# File path Open secret key file stored local
access_keys = functs.load_keys(path + '/keys.json')

# Create a connection to the Azure SQL database
# =============================================
conn_names = functs.load_connection_names(path + '\connection_names.json')
server = conn_names.sql_server
database = conn_names.sql_database
username = conn_names.sql_user
connection_string = 'DRIVER={ODBC Driver 13 for SQL Server};SERVER=' + server + ';DATABASE=' + database +';UID=' + username + ';PWD=' + access_keys.sqldb_pwd
    
# Connect to the database    
conn = pyodbc.connect(connection_string, autocommit = True)

# Specify Directories
# ===================
pipeline_dir = path + '/'
rscript_command ='C:/Program Files/R/R-4.0.2/bin/Rscript'

args = ['C:/MyApps']

try:
    os.chdir(pipeline_dir)    
# Catch invalid path    
except WindowsError as e:
    print("Error:" + str(e))
# Catch file not found error    
except OSError as e:    
    print("Error:" + str(e))
else :        
    print('Step 1: Downloading & saving raw GTFS data to SQL DB')
    script = 'ingestGtfs.R'
    cmd = [rscript_command, pipeline_dir + script] + args    
    # check_output will run the command and store to result
    subprocess.check_output(cmd, universal_newlines=True)        
    
finally :
    # return to root directory
    os.chdir(root_folder + '\dapTbElectricDublinBus')







