source('global.R')
library(shinyalert)

header <- dashboardHeader(title = "DAP Team B Group Project", titleWidth = 220)

sidebar <- dashboardSidebar(
  useShinyjs(), 
  useShinyalert(),
  tags$head(
    tags$link(rel = "stylesheet", type = "text/css", href = "custom.css")),
  tags$style(rel = "stylesheet", type = "text/css", href = "custom.css"),
  width=220,
  sidebarMenu(
    br(),
    div(img(src="bus-front-green-exp.svg"), style="margin-top: 10px; margin-left: 13px; margin-right: 30px; margin-bottom: 10px;"),
    br(),
    menuItem("Network Summary", tabName = "network", icon = icon("bar-chart")),
    menuItem("Route Visualization", tabName = "analysis", icon = icon("superpowers")),
    br(),
    div(conditionalPanel(condition="$('html').hasClass('shiny-busy')",
                         img(src="gears.gif")), style="margin-left: 25px;")
  )
)

body <- dashboardBody(
  tabItems(
    tabItem(
      tabName = "analysis",
      fluidRow(
        box(width=12,
            title = strong(tags$i(class="fa fa-bullseye fa-fw"), "Electric Dublin Bus"), 
            collapsible = TRUE,
            solidHeader = TRUE,
            status = "primary",
            fluidRow(
              column(6,
                div(uiOutput('showRouteSelector'), style = 'margin-left: 14px; margin-top: 5px; display: inline-block; vertical-align: top;'),
                div(uiOutput('showRouteNameSelector'), style = 'margin-left: 14px; margin-top: 5px; display: inline-block; vertical-align: top;'),
                div(uiOutput('showServiceSelector'), style = 'margin-left: 14px; margin-top: 5px; display: inline-block; vertical-align: top;'),
                div(uiOutput('showBlockSelector'), style = 'margin-left: 14px; margin-top: 5px; display: inline-block; vertical-align: top;'),
                div(uiOutput('showActionButton'), style = 'margin-left: 14px; margin-top: 5px; display: inline-block; vertical-align: top;'),
                div(uiOutput('showMainBusMap')),
                div(uiOutput('showTripTable'))
              ),
              column(6,
                div(uiOutput('showDeadTripInfo')),
                # div(
                #   conditionalPanel(
                #     condition = "$('html').hasClass('shiny-busy')",
                #     div(tags$i(class="fas fa-spinner fa-pulse"), span("Loading data...", style = 'margin-left: 4px;'),
                #         class = "pulsate load-msg"),
                #     style = "margin: 15px;"
                #   )
                # ),
                div(uiOutput('showRoutePlots'))
              )
            ),
            br(), br(), br(), br(), br(), br(), br(), br()
        )
      )
    ),
    tabItem(
      tabName = "network",
      fluidRow(
        box(width=12,
            title = strong(tags$i(class="fa fa-bullseye fa-fw"), "Electric Dublin Bus"), 
            collapsible = TRUE,
            solidHeader = TRUE,
            status = "primary",
            fluidRow(
              column(12,
                div(
                  div(uiOutput('showRangePlotTitle')),
                  div(plotlyOutput('rangeBreakdownPlot'), style = 'height: 200px;'),
                  div(uiOutput('showRangePlotNotes')), style = 'display: inline-block; vertical-align: top;'
                ),
                div(
                  div(uiOutput('showHistoPlotTitle')),
                  div(plotlyOutput('rangeHistoPlot'), style = 'margin-bottom: 25px;'),
                  style = 'display: inline-block; vertical-align: top; margin-left: 25px; height: 220px;' 
                ),
                div(reactableOutput("networkTable"), style = 'margin-right: 30px; margin-top: 10px;', class = "reactBox")
              )
            ),
            br(), br(), br(), br(), br(), br(), br(), br()
        )
      )
    ) 
  )
)

dashboardPage(title = "DAP Team B Project", header, sidebar, body, skin = "green")