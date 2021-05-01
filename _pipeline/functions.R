library(DBI)
library(pool)

"%+%" <- function(...) paste0(...)

DB_PASSWORD_FILE_NAME <- "keys.json"

# read config from local config file 
passwordDb_config <- fromJSON(file = DB_PASSWORD_FILE_NAME) # SQL database connection on

runningOnShinyApps <- function() {
  if (Sys.getenv('SHINY_PORT') == "") { 
    return(FALSE)  # NOT running on shinyapps.io
  } else {
    return(TRUE)  # Running on shinyapps.io
  }
}

# create function to get local odbc driver from machine
getLocalDriverODBC <- function() {
  # in instances where there are >1 drivers, only take most recent, defined by a decresing sort function
  return(sort(unique(odbc::odbcListDrivers()$name[grep('ODBC', odbc::odbcListDrivers()$name, ignore.case = F, perl = T)]), decreasing=T)[1])
} 

# connect to the database, use a different server string formatting depending on windows (local) or linux (shinyapps)
getServerStr <- function(server) {
  if (runningOnShinyApps()) {
    return(server %+% ";Port=" %+% as.character(PORT))
  } else  { # local
    return("tcp:" %+% server %+% "," %+% as.character(PORT))
  }
}

# connect to the database, use a different driver if the application is on shinyapps.io
getDriverStr <- function() {
  if (runningOnShinyApps()) {
    return("FreeTDS;TDS_Version=7.2") 
  } else { # local
    return(getLocalDriverODBC())  # take ODBC driver name from machine, rather than hard coding it in as it can change dependign on version of MS SQL Server Mgmt Studio
  }
} 

formConnectionString <- function(database, server, username, password) {
  connectionString <- "Driver="   %+% getDriverStr() %+%  ";" %+%
    "Server="   %+% getServerStr(server) %+%  ";" %+%
    "Database=" %+% database   %+%  ";" %+%
    "Uid="      %+% username   %+%  ";" %+%
    "Pwd={"     %+% password   %+% "};" %+% # password stored in non-source-controlled file
    "Encrypt=yes;" %+%
    "TrustServerCertificate=no;" %+%
    "Connection Timeout=30;"
  return(connectionString)
}

# Get database pool.
getDbPool <- function(dbName = NA, serverName = NA) {
  if (is.na(dbName)) {
    stop("you must specify a database name")
  }
  if (is.na(serverName)) {
    serverName <- DEFAULT_SERVER
  }
  return(pool::dbPool(odbc::odbc(), .connection_string = formConnectionString(dbName, serverName, USERNAME, passwordDb_config$sqldb_pwd)))
}

getDbData <- function (query, connection_pool){
  con <- pool::poolCheckout(connection_pool)
  data <- DBI::dbGetQuery(con, query)
  poolReturn(con)
  return(data)
}

saveByChunk <- function(chunk_size, dat, table_name, connection_pool, replace = TRUE) {
  con <- pool::poolCheckout(connection_pool)
  #con <- connection_pool
  # Save data in chunks so that progress can be tracked
  # Split the data frame into chunks of chunk size or less
  chunkList <- split(dat, (seq(nrow(dat)) - 1) %/% chunk_size)
  # Now write each data chunk to the database 
  for (i in 1:length(chunkList)){
    print(paste0("Processing Batch ", i, " of ", length(chunkList)))
    data <- chunkList[[i]]
    names(data) <- gsub('ï..', '', names(data))
    if (i == 1 & replace == TRUE){
      print('Creating & writing to database table...')
      write <- DBI::dbWriteTable(con, name = table_name, value = data, overwrite = TRUE, row.names = FALSE)  
      if(write){
        print('Successful data write...')
      } else {
        print('Unsuccessful data write...')
      }
    } else {
      print('Appending data to database table...')
      write <- DBI::dbWriteTable(con, name = table_name, value = data, append = TRUE, row.names = FALSE) 
      if(write){
        print('Successful data write...')
      } else {
        print('Unsuccessful data write...')
      }
    }
  }
  poolReturn(con)
}

getStopName <- function(stop_id, connection_pool){
  con <- poolCheckout(connection_pool)
  query <- paste0("SELECT stop_name from stops WHERE stop_id = '", stop_id, "'")
  stop_name <- DBI::dbGetQuery(con, query)$stop_name[1]
  pool::poolReturn(con)
  rm(query)
  return(stop_name)
}

# Function for converting time in string H:M:S format to numeric seconds
toSeconds <- function(x){
  if (!is.character(x)) stop("x must be a character string of the form H:M:S")
  if (length(x)<=0)return(x)
  
  unlist(
    lapply(x,
           function(i){
             i <- as.numeric(strsplit(i, ':', fixed = TRUE)[[1]])
             if (length(i) == 3) 
               i[1] * 3600 + i[2] * 60 + i[3]
             else if (length(i) == 2) 
               i[1] * 60 + i[2]
             else if (length(i) == 1) 
               i[1]
           }  
    )  
  )  
} 