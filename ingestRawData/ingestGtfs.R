library(rvest)
library(stringr)
library(dplyr)

page <- xml2::read_html("https://transitfeeds.com/p/transport-for-ireland/782")

file <- page %>%
  html_nodes("a") %>%     # find all links
  html_attr("href") %>%   # get the url
  str_subset("\\.zip")    # find those that end in zip


download.file(
  url = file, 
  destfile = 'C:/MyApps/dapTbElectricDublinBus/ingestRawData/gtfs.zip'
)
