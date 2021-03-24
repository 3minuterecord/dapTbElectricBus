source("global.R")

library(reactable)
library(tidyr)
library(dplyr)

shinyServer(function(input, output, session) {
  
  conPool <- getDbPool(DATABASE)
  
  map_class <- reactiveValues(class = NULL)
  
  output$showMainBusMap <- renderUI({
    req(tripShapes())
    div(leafletOutput("busGeoMap"), class = map_class$class)
  })
  
  
  # Get trip_shapes lat and lon json
  tripShapes <- reactive({
    con <- poolCheckout(conPool)
    # Get the latest count
    query <- "SELECT shape_id, shape_pt_lat, shape_pt_lon FROM shapes"
    data <- DBI::dbGetQuery(con, query)
    poolReturn(con)
    return(data)
  })
  
  
  # Bus Geo Map.
  output$busGeoMap <- renderLeaflet({
    outputMap <- leaflet() %>%
      addFullscreenControl(position = "topleft", pseudoFullscreen = FALSE) %>%
      addProviderTiles("OpenStreetMap.Mapnik", group = "OpenStreetMap") %>%
      addProviderTiles("CartoDB.Positron", group = "Greyscale") %>%
      addProviderTiles("Esri.WorldImagery", group = "Satellite") %>%
      addFullscreenControl(position = "topleft", pseudoFullscreen = FALSE) %>%
      
      # Add radio buttons to toggle Pipe and Area layers.
      addLayersControl(
        baseGroups = c("Greyscale", "OpenStreetMap", "Satellite"),
        overlayGroups = c("Selected Bus Route"),
        options = layersControlOptions(collapsed = TRUE)
      ) %>%
      
      addScaleBar(position = "bottomright")
    
    # Add trip shape
    tripShapesData <- tripShapes()
    tripIds  <- unique(tripShapesData$shape_id)
    
    # Create color palette for list of trips.
    pal <- colorFactor(viridis(length(tripIds)), unlist(tripIds))
    
    j = 1
    withProgress(message = 'Loading shapes...', value = 0, {
      for (id in tripIds){
        incProgress(1/length(tripIds), detail = paste(j, " of ", length(tripIds)))
        j = j + 1
        coords <- tripShapesData %>% 
          filter(shape_id == id)
          
        latitudes <- coords$shape_pt_lat
        longitudes <- coords$shape_pt_lon
        tripPlotData <- data.frame(lats = c(unlist(latitudes)), lons = c(unlist(longitudes)))
        # trip shape plot.
        outputMap <- outputMap %>%
          addPolylines(
            data = tripPlotData,
            lat = ~lats,
            lng = ~lons,
            label = 'Trip-'%+% id,
            #color = '#B4DA86',
            color = ~pal(id),
            weight = 2,
            opacity = 1
          )
      }
    })
    map_class$class <- 'map-box'
    return(outputMap)
  })
})