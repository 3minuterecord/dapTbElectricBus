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
# Required	Transit routes. A route is a group of trips that are displayed to riders as a single service.
 
# trips.txt	
# Trips for each route. A trip is a sequence of two or more stops that occur during a specific time period.
 
# stop_times.txt
# Required	Times that a vehicle arrives at and departs from stops for each trip.
 
# calendar.txt	
# Conditionally required	Service dates specified using a weekly schedule with start and end dates. 
# This file is required unless all dates of service are defined in calendar_dates.txt.
 
# calendar_dates.txt	
# Conditionally required	Exceptions for the services defined in the calendar.txt.
# If calendar.txt is omitted, then calendar_dates.txt is required and must contain all dates of service.


# Create an emtpy list to hold the GTFS data
data <- list()

# Get a vector of file names that have been unzipped
files <- list.files('ingestRawData/raw/')

# Loop through and add each file as an element to the list
for (file in 1:length(files)){
  file <- files[file]
  table_name <- gsub('.txt', '', file)
  data_add <- read.table(paste0('ingestRawData/raw/', file), sep = ',', header = TRUE)
  names(data_add) <- gsub('ï..', '', names(data_add)) # Clean any strange chars that import with field name
  data[[table_name]] <- data_add
  rm(data_add, table_name, file)
}





