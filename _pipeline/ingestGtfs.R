# Ingest Raw GTFS Data
# ====================

# Fetch command line arguments
myArgs <- commandArgs(trailingOnly = TRUE)

# Define the root folder where the repo has been downloaded to
root_folder <- as.character(myArgs[1]) # 'C:/MyApps'
setwd(paste0(root_folder, '/dapTbElectricDublinBus/_pipeline'))

# Database test or production?
db_env <- myArgs[3] # test or prod

library(rjson)
library(rvest)
library(stringr)
library(xml2)
library(pool)
library(DBI)
library(dplyr)
source('functions.R')


# Get DB connection details (SQL azure) for storage of raw GTFS data
# ===================================================================
# TODO --- Wrap in tryCatch
KEYS_FILE_NAME <- 'keys.json'
CONS_FILE_NAME <- 'connection_names.json'
DATABASE <- paste0(fromJSON(file = CONS_FILE_NAME)$sql_database, db_env)
DEFAULT_SERVER <- gsub('tcp:', '', fromJSON(file = CONS_FILE_NAME)$sql_server)
PORT <- fromJSON(file = CONS_FILE_NAME)$sql_port
USERNAME <- fromJSON(file = CONS_FILE_NAME)$sql_user
passwordDb_config <- fromJSON(file = KEYS_FILE_NAME)
depot_mappings <- read.csv('depot_mapping.csv', stringsAsFactors = F)


# Create function to download the latest raw GTFS data
# NOTE: Use tryCatch for error / warning handling
# ====================================================
ingestGtfs <- function(root, feed = 'project') {
  out <- tryCatch(
    {
      # Define webpage for Dublin Bus GTFS data 
      if (feed == 'project'){
        # Download the feed form the 6th April 2021 (project basis)
        file <- "https://transitfeeds.com/p/transport-for-ireland/782/20210406/download"
      } else {
        # Download the latest feed
        page <- xml2::read_html("https://transitfeeds.com/p/transport-for-ireland/782")  
        # Get the url for the zip file
        file <- page %>%
          rvest::html_nodes("a") %>%     # find all links
          rvest::html_attr("href") %>%   # get the url
          stringr::str_subset("\\.zip")    # find those that end in zip
      }
      
      # Download the data as a zip file
      zip_file_Location <- paste0(root, '/dapTbElectricDublinBus/_pipeline/gtfs.zip')
      #download.file(url = file, destfile = zip_file_Location, mode = 'wb')
      
      # Unzip the data to a raw folder
      # This will create a series of txt files for each GTFS 'table'
      unzip(
        zipfile = zip_file_Location,
        exdir = paste0(root, '/dapTbElectricDublinBus/_pipeline/raw')
        )

      # Open the GTFS files and save to SQL DB
      # ======================================
      
      # Create an empty list to hold the GTFS data
      data <- list()
      
      # Define location of pipeline script
      file_dir <- '_pipeline'
      
      # Get a vector of file names that have been unzipped
      files <- list.files('raw/')
      
      # Avoid readtable cutting back precision
      options(digits = 22)
      
      # Loop through and add each file as an element to the list
      for (file in 1:length(files)){
        file <- files[file]
        table_name <- gsub('.txt', '', file)
        # Remove the BOM if present in the file (use UTF... encoding)
        data_add <- read.table(paste0('raw/', file), sep = ',', header = TRUE, fileEncoding = "UTF-8-BOM")
        names(data_add) <- gsub('ï..', '', names(data_add)) # Clean any strange chars that import with field name
        data[[table_name]] <- data_add
        rm(data_add, table_name, file)
      }

      # Open a connection pool & save the data
      conPool <- getDbPool(DATABASE)
      
      for (i in 1:length(names(data))){
        table_name <- names(data)[i]
        dat <- data[[names(data)[i]]]
        # Remove any strange chars in col names
        names(dat) <- gsub('ï..', '', names(dat))
        print(table_name)
        print(head(dat))
        # Seems to be an issue creating a table with the name 'routes'
        if (table_name == 'routes') {table_name <- 'bus_routes'}
        if (table_name == 'stop_times') next
        if (table_name == 'shapes') next
        # Now save in row chunks to SQL DB
        saveByChunk(
          chunk_size = 5000, 
          dat = dat, 
          table_name = table_name, 
          connection_pool = conPool, 
          replace = TRUE
        )
      }
      
      # Bus Depot Coordinates
      # =====================
      # Coordinates from Google Maps pins
      depots <- data.frame(
        name = c('Ringsend', 'Sumerhill', 'Simmonscourt', 'Conyngham'),
        lat = c(53.34467535286916, 53.357791006125375, 53.31966245934526, 53.350004073703836),
        lon = c(-6.233444586417399, -6.255073919093893, -6.232071295453812, -6.302624118708089)
      )
      # Now save in row chunks to SQL DB
      saveByChunk(
        chunk_size = 5000, 
        dat = depots, 
        table_name = 'depots', 
        connection_pool = conPool, 
        replace = TRUE
      )
      'Complete'
    },
    error = function(cond) {
      message("Error message:")
      message(cond)
      return(NA)
    },
    warning = function(cond) {
      message("Warning message:")
      message(cond)
      return(NULL)
    },
    finally = {
      message('')
      message(paste("Process ended..."))
    }
  )
  return(out)
}

# Now run the function with the argument from cmd
ingestGtfs(root = root_folder)



