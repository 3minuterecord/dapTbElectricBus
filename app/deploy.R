library(rsconnect)

rsconnect::deployApp(appDir = "app",
                     appFiles = c('password.json', 'global.R', 'Server.R', 'ui.R','www'),
                     account = "orb10x",
                     server = "shinyapps.io",
                     appName = "dapTbElectricBus",
                     appTitle = "dapTbElectricBus",
                     launch.browser = function(url) {message("Deployment completed: ", url)},
                     lint = FALSE,
                     metadata = list(asMultiple = FALSE,
                                     asStatic = FALSE),
                     logLevel = "verbose")