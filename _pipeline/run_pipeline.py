# INGEST RAW GTFS DATA & SAVE TO AZURE SQL DB
# ===========================================
import subprocess
# Define command and arguments
command ='C:/Program Files/R/R-4.0.2/bin/Rscript'
path2script ='C:/MyApps/dapTbElectricDublinBus/_pipeline/ingestGtfs.R'
# Build subprocess command
cmd = [command, path2script]
subprocess.run(cmd)

#%%

