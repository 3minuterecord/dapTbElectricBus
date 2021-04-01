source("global.R")

library(reactable)
library(tidyr)
library(dplyr)

shinyServer(function(input, output, session) {
  
  conPool <- getDbPool(DATABASE)
  
  # Get bus depot coordinates
  depots <- reactive({
    con <- poolCheckout(conPool)
    query <- "SELECT * FROM depots"
    data <- DBI::dbGetQuery(con, query)
    poolReturn(con)
    return(data)
  })
  
  # Get a vector of unique routes that have trips specified
  routesVector <- reactive({
    con <- poolCheckout(conPool)
    query <- "SELECT DISTINCT route_id FROM trips"
    data <- DBI::dbGetQuery(con, query)
    poolReturn(con)
    return(data$route_id)
  })
  
  # Get the short name of the selected route, e.g, 16A
  routeName <- reactive({
    con <- poolCheckout(conPool)
    query <- paste0("SELECT route_short_name FROM bus_routes WHERE route_id = '", routesVector()[routeVectorCounter$num], "'")
    data <- DBI::dbGetQuery(con, query)
    poolReturn(con)
    return(data$route_short_name)
  })
  
  # Get trip details for the selected route
  tripsData <- reactive({
    con <- poolCheckout(conPool)
    query <- paste0("SELECT trip_id, service_id FROM trips WHERE route_id = '", input$selected_route, "'")
    data <- DBI::dbGetQuery(con, query)
    poolReturn(con)
    return(data)
  })
  
  stops <- reactive({
    req(input$selected_route)
    con <- poolCheckout(conPool)
    query <- paste0("SELECT t.route_id, t.trip_id, t.service_id, s.arrival_time, s.departure_time, 
    s.stop_id, s.stop_headsign, s.shape_dist_traveled, t.direction_id  
    FROM trips t LEFT JOIN stop_times s ON t.trip_id = s.trip_id WHERE t.trip_id IN (",
    paste0(sprintf("'%s'", unique(tripsData()$trip_id)), collapse = ', '), ") AND t.service_id = '", unique(tripsData()$service_id[1]), "'")
    data <- DBI::dbGetQuery(con, query)
    poolReturn(con)
    if(nrow(data) != 0){
      # Create quasi block number data based on departure time diffs
      data$quasi_block <- c(0, diff(toSeconds(data$departure_time)))
      data$quasi_block <- ifelse(data$quasi_block < 0, 1, 0) 
      bounds <- length(data$quasi_block[data$quasi_block == 1])
      data$quasi_block[data$quasi_block == 1] <- (2:(bounds + 1))
      data$quasi_block[1] <- 1
      data$quasi_block <- ifelse(data$quasi_block == 0, NA, data$quasi_block)
      data$quasi_block <- zoo::na.locf(data$quasi_block)
    }
    return(data)
  })
  
  shapeIds <- reactive({
    req(input$selected_block)
    trips <- stops() %>%
      filter(quasi_block == input$selected_block)
    con <- poolCheckout(conPool)
    query <- paste0("SELECT shape_id FROM trips WHERE trip_id IN (", 
                    paste0(sprintf("'%s'", unique(trips$trip_id)), collapse = ', '), ")")
    data <- DBI::dbGetQuery(con, query)
    poolReturn(con)
    return(data$shape_id)
  })
  
  start_and_ends <- reactiveValues()
  
  # Get shapes details for the trips associated with the selected route
  shapeData <- reactive({
    con <- poolCheckout(conPool)
    query <- paste0("SELECT shape_id, shape_pt_lat, shape_pt_lon FROM shapes WHERE shape_id IN (", 
                    paste0(sprintf("'%s'", shapeIds()), collapse = ', '), ")")
    data <- DBI::dbGetQuery(con, query)
    
    out <- data.frame()
    for (shape in unique(data$shape_id)){
      df <- data %>%
        filter(shape_id == shape) 
      out_add <- data.frame(
        shape_id = rep(shape, 2),
        position = c('start', 'end'),
        lat = c(head(df$shape_pt_lat, 1), tail(df$shape_pt_lat, 1)),
        lon = c(head(df$shape_pt_lon, 1), tail(df$shape_pt_lon, 1))
      )
      out <- rbind(out, out_add)
    }
    start_and_ends$data <- out
    rm(out, out_add)
    
    poolReturn(con)
    return(data)
  })
  
  # Create UI elements for selecting route to visualize
  output$showRouteSelectorControls <- renderUI({
    div(
      div(
        selectInput(
          'selected_route',
          'Route Id',
          choices = routesVector(),
          selected = routesVector()[routeVectorCounter$num],
          width = 150
        ), style = 'display: inline-block;'
      ),
      # For now, assume navigation is by route id, show (but disable) name
      div(
        shinyjs::disabled(textInput(
          'selected_route_name',
          'Name',
          value = routeName(),
          width = 90
        )), style = 'display: inline-block; vertical-align: top;'
      ),
      div(
        shinyjs::disabled(textInput(
          'selected_service',
          'Service',
          value = unique(tripsData()$service_id[1]),
          width = 90
        )), style = 'display: inline-block; vertical-align: top;'
      ),
      # Create forward and back buttons for faster navigation through the list of routes
      div(
        actionButton(
          'last_route',
          'Back',
          width = 60
        ), style = 'display: inline-block; margin-left: 10px; margin-top: 26px; vertical-align: top;'
      ),
      div(
        actionButton(
          'next_route',
          'Next',
          width = 60
        ), style = 'display: inline-block; margin-left: 10px; margin-top: 26px; vertical-align: top;'
      )
    )
  })
  
  # Create UI elements for selecting route to visualize
  output$showBlockSelectorControls <- renderUI({
    if(nrow(stops()) == 0){return(NULL)}
    div(
      div(
        selectInput(
          'selected_block',
          'Block',
          choices = unique(stops()$quasi_block),
          #selected = routesVector()[routeVectorCounter$num],
          width = 100
        ), style = 'display: inline-block; margin-left: 15px;'
      ),
      # Create forward and back buttons for faster navigation through the list of routes
      div(
        actionButton(
          'last_block',
          'Back',
          width = 60
        ), style = 'display: inline-block; margin-left: 10px; margin-top: 26px; vertical-align: top;'
      ),
      div(
        actionButton(
          'next_block',
          'Next',
          width = 60
        ), style = 'display: inline-block; margin-left: 10px; margin-top: 26px; vertical-align: top;'
      )
    )
  })
  
  # Create a counter for navigating through the list of routes
  # Initialize = 1
  routeVectorCounter <- reactiveValues(num = 1)
  
  # If the drop down for routes is accessed and changes by more that a step of 1
  # Update the counter to the appropriate index
  observeEvent(input$selected_route, {
    blockVectorCounter$num <- 1
    index <- which(routesVector() == input$selected_route)
    if (abs(index - routeVectorCounter$num) != 0) {
      routeVectorCounter$num <- index  
    }
  })
  
  # If the next button is pressed, udpate the drop down selected & increase the counter by 1
  # As long as you are not at the end of the list
  observeEvent(input$next_route, {
    if (routeVectorCounter$num != length(routesVector())){
      updateSelectInput(
        'selected_route',
        'Route Id',
        choices = routesVector(),
        selected = routesVector()[routeVectorCounter$num + 1], 
        session = session
      )
      routeVectorCounter$num <- routeVectorCounter$num + 1  
    }
  })
  
  # If the back button is pressed, udpate the drop down selected & decrease the counter by 1
  # As long as you are not at the start of the lis
  observeEvent(input$last_route, {
    if (routeVectorCounter$num != 1){
      updateSelectInput(
        'selected_route',
        'Route Id',
        choices = routesVector(),
        selected = routesVector()[routeVectorCounter$num - 1], 
        session = session
      )
      routeVectorCounter$num <- routeVectorCounter$num - 1  
    }
  })
  
  blockVectorCounter <- reactiveValues(num = 1)
  
  observeEvent(input$selected_block, {
    index <- which(unique(stops()$quasi_block) == input$selected_block)
    if (abs(index - blockVectorCounter$num) != 0) {
      blockVectorCounter$num <- index  
    }
  })
  
  # If the next button is pressed, update the drop down selected & increase the counter by 1
  # As long as you are not at the end of the list
  observeEvent(input$next_block, {
    if (blockVectorCounter$num != length(unique(stops()$quasi_block))){
      updateSelectInput(
        'selected_block',
        'Block',
        choices = unique(stops()$quasi_block),
        selected = unique(stops()$quasi_block)[blockVectorCounter$num + 1], 
        session = session
      )
      blockVectorCounter$num <- blockVectorCounter$num + 1  
    }
  })
  
  # If the back button is pressed, udpate the drop down selected & decrease the counter by 1
  # As long as you are not at the start of the lis
  observeEvent(input$last_block, {
    if (blockVectorCounter$num != 1){
      updateSelectInput(
        'selected_block',
        'Block',
        choices = unique(stops()$quasi_block),
        selected = unique(stops()$quasi_block)[blockVectorCounter$num - 1], 
        session = session
      )
      blockVectorCounter$num <- blockVectorCounter$num - 1  
    }
  })
  
  # Create a reactive value for the map CSS class so that it can be delayed until data is ready
  # This avoids the box shadow appearing before the data
  map_class <- reactiveValues(class = NULL)
  
  # Create the Geo Map for the selected bus route
  output$busGeoMap <- renderLeaflet({
    if(nrow(stops()) == 0){return(NULL)}
    req(input$selected_route)
    
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
    tripShapesData <- shapeData()
    tripIds  <- unique(tripShapesData$shape_id)
    print(length(tripIds))
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
            color = '#70A432',
            #color = ~pal(id),
            weight = 2,
            opacity = 1
          )
      }
    })
    
    # Plot block start and end coordinates as pins
    start_and_ends <- start_and_ends$data
    print(start_and_ends)
    if(!is.null(start_and_ends) && length(start_and_ends) > 0){
      for(location in start_and_ends$shape_id){
        df <- start_and_ends %>% filter(shape_id == location)
        outputMap <- outputMap %>% 
        addAwesomeMarkers(
          data = df, lng = ~lon, lat = ~lat,
          label = 'start/end',
          icon = awesomeIcons(
            icon = 'radio-button-on',
            library = 'ion',
            markerColor = 'green',
            iconColor = 'white'
            )
          )
      }
    }
    
    # Bus depots
    outputMap <- outputMap %>% 
      addAwesomeMarkers(
        data = depots(), lng = ~lon, lat = ~lat,
        label = ~name,
        icon = awesomeIcons(
          text = '',
          markerColor = '#D60000',
          iconColor = 'white'
        )
      )
    
    map_class$class <- 'map-box'
    return(outputMap)
  })
  
  # Render the bus map
  output$showMainBusMap <- renderUI({
    req(input$selected_route)
    req(shapeData())
    req(input$selected_block)
    div(leafletOutput("busGeoMap"), class = map_class$class)
  })
  
  # Show the reactable table view of trips for selected route
  output$showTripTable <- renderUI({
    div(reactableOutput("tripTable"), class = "reactBox")
  })
  
  # Create reactable table view of trips for selected route
  output$tripTable <- reactable::renderReactable({
    if(nrow(stops()) == 0){
      data <- stops() %>% mutate(quasi_block = '')  
    } else {
      req(input$selected_block)
      data <- stops() %>% filter(quasi_block == input$selected_block)  
    }
    
    reactable(
      data,
      filterable = FALSE,
      searchable = TRUE,
      #defaultSorted = list(BudgetSpent = "desc"),
      selection = "single",
      selectionId = "tableId1",
      defaultPageSize = 1000,
      showPageSizeOptions = TRUE,
      pageSizeOptions = c(10, 20, 50, 250, 500, 1000),
      onClick = "select",
      resizable = TRUE,
      bordered = TRUE,
      highlight = TRUE,
      wrap = FALSE,
      class = "react-table",
      rowStyle = list(cursor = "pointer"),
      defaultColDef = colDef(headerStyle = list(background = "#f7f7f8"))
    )
  })
}) 