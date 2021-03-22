import urllib

class UrlHandler(object):
    def __init__(self, *args):
        self.arg = "Put args here"
    def __call__(self, callargs):
        if callargs == "Call URL":
            "do something in the URL"
    
    def callURL(self):
        return "call URL"