import subprocess
import os

pipeline_dir = 'C:/MyApps/dapTbElectricDublinBus/_pipeline/'
rscript_command ='C:/Program Files/R/R-4.0.2/bin/Rscript'

try:
    os.chdir(pipeline_dir)    
# Catch invalid path    
except WindowsError as e:
   print("Error:" + str(e))
# Catch file not found error    
except OSError as e:    
   print("Error:" + str(e))
else :    
    # STEP 1 - INGEST RAW GTFS DATA & SAVE TO AZURE SQL DB
    # ====================================================
    # Build & run subprocess command
    # WARNING --- Saving the data to the DB takes sevral hours.
    script ='ingestGtfs.R'
    cmd = [rscript_command, pipeline_dir + script]
    subprocess.run(cmd)
    
    # STEP 2 - CREATE BLOCKS, DEAD TRIP & DEAD LEG INFO
    # =================================================
    # Build & run subprocess command
    # WARNING --- This processing script takes sevral hours to run.
    script ='createBlockInfo.R'
    cmd = [rscript_command, pipeline_dir + script]
    subprocess.run(cmd)
    
    # STEP 3 - GET RAW ROUTE INFO FOR DEAD LEGS & DEAD TRIPS
    # ======================================================
    import ingestNonGtfsRoutes
    
    def service_func_ingr():
        print('Running ingest non-GTFS route script...')
    
    if __name__ == '__main__':
        # if this scipt is executed as script, run:
        service_func_ingr()
        ingestNonGtfsRoutes.run_all_ingr()
    
    # STEP 4 - EXTRACT RAW ROUTE DATA & TRANSFORM
    # ======================================================
    import extractTransformLoadRoutes
    
    def service_func_etlr():
        print('Running extract & transfrom non-GTFS script...')
    
    if __name__ == '__main__':
        # if this scipt is executed as script, run:
        service_func_etlr()
        extractTransformLoadRoutes.run_all_etlr()    
    
    # STEP 5 - CREATE NETWORK SUMMARY INFO
    # ====================================
    # Build & run subprocess command
    # WARNING --- This processing script takes sevral hours to run.
    script ='createBlockSummary.R'
    cmd = [rscript_command, pipeline_dir + script]
    subprocess.run(cmd)
    
finally :
    # return to root directory
    os.chdir('C:\MyApps\dapTbElectricDublinBus')

