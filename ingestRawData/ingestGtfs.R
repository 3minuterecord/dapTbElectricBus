library(rvest)
library(stringr)
library(xml2)
library(dplyr)

# Define webpage for Dublin Bus GTFS data 
page <- xml2::read_html("https://transitfeeds.com/p/transport-for-ireland/782")

# Get the url for the zip file
file <- page %>%
  rvest::html_nodes("a") %>%     # find all links
  rvest::html_attr("href") %>%   # get the url
  stringr::str_subset("\\.zip")    # find those that end in zip

# Download the data as a zip file
download.file(
  url = file, 
  destfile = 'C:/MyApps/dapTbElectricDublinBus/ingestRawData/gtfs.zip'
)

# Unzip the data to a raw folder
# This will create a series of txt files for each GTFS 'table'
unzip(
  'C:/MyApps/dapTbElectricDublinBus/ingestRawData/gtfs.zip',
  exdir = 'ingestRawData/raw')


# GTFS File Descriptions
# ======================
# Ref.:
# https://developers.google.com/transit/gtfs/reference

# agency.txt 
# Transit agencies with service represented in this dataset.
 
# stops.txt
# Stops where vehicles pick up or drop off riders. Also defines stations and station entrances.
 
# routes.txt	
# A route is a group of trips that are displayed to riders as a single service.
 
# trips.txt	
# Trips for each route. 
# A trip is a sequence of two or more stops that occur during a specific time period.
 
# stop_times.txt
# Times that a vehicle arrives at and departs from stops for each trip.
 
# calendar.txt	
# Service dates specified using a weekly schedule with start and end dates. 
# This file is required unless all dates of service are defined in calendar_dates.txt.
 
# calendar_dates.txt	
# Exceptions for the services defined in the calendar.txt.
# If calendar.txt is omitted, then calendar_dates.txt is required and must contain all dates of service.

# Notes on specific fields from GTFS specification
# ================================================

# direction_id
# Indicates the direction of travel for a trip. This field is not used in routing; 
# it provides a way to separate trips by direction when publishing time tables. Valid options are:
# 0 - Travel in one direction (e.g. outbound travel).
# 1 - Travel in the opposite direction (e.g. inbound travel).

# block_id ~ Not provided in Diblin Bus data?
# Identifies the block to which the trip belongs. 
# A block consists of a single trip or many sequential trips made using the same vehicle, 
# defined by shared service days and block_id. A block_id can have trips with different service days, 
# making distinct blocks. See the example below

# Create an emtpy list to hold the GTFS data
data <- list()

# Get a vector of file names that have been unzipped
files <- list.files('ingestRawData/raw/')

# Avoid readtable cutting back precision
options(digits = 22)

# Loop through and add each file as an element to the list
for (file in 1:length(files)){
  file <- files[file]
  table_name <- gsub('.txt', '', file)
  data_add <- read.table(paste0('ingestRawData/raw/', file), sep = ',', header = TRUE)
  names(data_add) <- gsub('ï..', '', names(data_add)) # Clean any strange chars that import with field name
  data[[table_name]] <- data_add
  rm(data_add, table_name, file)
}

library(pool)
library(DBI)
library(rjson)

# The app's database (SQL azure)
DATABASE <- "electricbus-eastus-prod-temp"

"%+%" <- function(...) paste0(...)

DEFAULT_SERVER <- "electricbus-temp.database.windows.net"
PORT <- 1433
USERNAME <- "teamadmin"

DB_PASSWORD_FILE_NAME <- "password.json"

# read config from local config file 
passwordDb_config <- fromJSON(file = DB_PASSWORD_FILE_NAME) # SQL database connection on Azure

conPool <- getDbPool(DATABASE)
con <- poolCheckout(conPool)

for (i in 1:length(names(data))){
  table_name <- names(data)[i]
  dat <- data[[names(data)[i]]]
  print(table_name)
  print(head(dat))
  if (table_name == 'routes') {
    # Seems to be an issue creating a table with the name 'routes'
    DBI::dbWriteTable(con, name = 'bus_routes', value = dat, overwrite = TRUE)    
  } else {
    DBI::dbWriteTable(con, name = table_name, value = dat, overwrite = TRUE)    
  }
}


# Bus Depot Coordinates
# Coordinates from Google Maps pins
depots <- data.frame(
  name = c('Ringsend', 'Sumerhill', 'Simmonscourt', 'Conyngham'),
  lat = c(53.34467535286916, 53.357791006125375, 53.31966245934526, 53.350004073703836),
  lon = c(-6.233444586417399, -6.255073919093893, -6.232071295453812, -6.302624118708089)
)
DBI::dbWriteTable(con, name = 'depots', value = depots, overwrite = TRUE)  

depot_mappings <- read.csv('C:/MyApps/dapTbElectricDublinBus/ingestRawData/depot_mapping.csv', stringsAsFactors = F)

poolReturn(con)
