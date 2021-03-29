import pyodbc

class Azure():
    def __init__(self,in_config):
        self.in_config = in_config
    def __call__(self, callargs):
        if callargs == "Call URL":
            "do something in the URL"

    def ReturnBusLocation(self):
        
        pass
    
    def GetCredentials(self):
        pass

    def AzureDBConnect(self):
        print(self.in_config.SQLDriver)
        conn = pyodbc.connect(f'''DRIVER={self.in_config.SQLDriver};
                                  SERVER={self.in_config.SQLServer};
                                  PORT=1433;
                                  DATABASE={self.in_config.SQLDatabase};
                                  UID={self.in_config.SQLUser};
                                  PWD={self.in_config.SQLPass}''')
        cursor = conn.cursor()
        return cursor