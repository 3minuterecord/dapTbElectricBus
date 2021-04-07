library(shiny)
library(shinydashboard)
library(shinyWidgets) # for toggle switch
library(shinyalert)
library(shinyjs)
library(pool)
library(reactable)
library(stringr)
library(plotly)
library(leaflet)
library(leaflet.extras)
library(leafpm)
library(DBI)
library(rjson)
library(viridis)

# The app's database (SQL azure)
DATABASE <- "electricbus-eastus-prod-temp"

"%+%" <- function(...) paste0(...)

DEFAULT_SERVER <- "electricbus-temp.database.windows.net"
PORT <- 1433
USERNAME <- "teamadmin"

DB_PASSWORD_FILE_NAME <- "password.json"

# read config from local config file 
passwordDb_config <- fromJSON(file = DB_PASSWORD_FILE_NAME) # SQL database connection on Azure

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
  return(pool::dbPool(odbc::odbc(), .connection_string = formConnectionString(dbName, serverName, USERNAME, passwordDb_config$password)))
}

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

# Add 24hrs to all transitions so that we can cehck for the scenario where a consecutive 
# stops on a trip straddle midnight
#stops$mod_time <- toSeconds(stops$departure_time) + (stops$quasi_block * 24 * 60 * 60)
#stops$diff_mod <- c(0, diff(stops$mod_time))

# # How many of these cases are less than a reasonable gap
# # i.e., if there is greater than a couple of hrs there it is not practical to assume 
# # it is part of the same block
# checks <- sum(stops$diff_mod < REASONABLE_GAP & stops$quasi_block == 1)
# if (checks >= 1){
#   # Get the index of cases where there is a short gap
#   index <- which(stops$diff_mod < REASONABLE_GAP & stops$quasi_block == 1)
#   # Reset the block markers to zero
#   stops$quasi_block[index] <- 0
#   # For each index, check the next time to see if it is reasonable to 
#   # say it is connected to the block or part of a new block
#   for (i in 1:checks){
#     j = 1
#     repeat{
#       chk_i <- stops$diff_time[index[i] + j]
#       if (chk_i < REASONABLE_GAP){
#         j = j + 1 # It is assumed to be part of the block, check the next...
#       } else {
#         # When there is an unreasonable gap, mark the block transition & break...
#         stops$quasi_block[index[i] + j] <- 1
#         break
#       } 
#     }  
#   }
# }