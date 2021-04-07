import time

# Create function to save tabulated data to Azure SQL db
def saveLogInfo (table, df, eng, chunks = 10000):
    s = time.time()
    df.to_sql(table, eng, if_exists = 'replace', chunksize = chunks, index = False)
    print('Time taken: ' + str(round(time.time() - s, 1)) + 's')
    return(None)

