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
