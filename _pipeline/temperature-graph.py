# import required libraries

import pandas as pd
import pyodbc
import numpy as np
import math
import scipy
import plotly.graph_objects as go
from urllib import parse
import sqlalchemy
import scipy.stats as stats
import csv
import pandas.io.sql as sqlio


# string required to connect to database
connecting_string = 'DRIVER={ODBC Driver 13 for SQL Server};SERVER=tcp:electricbus.database.windows.net;DATABASE=electricbus-eastus-production;UID=teamadmin;PWD=fghTgshY&th*%4;PORT=1433'


# pull data from the server
sql = """
SELECT * FROM temperature_data
"""
connection = pyodbc.connect(connecting_string)

temp_data = sqlio.read_sql_query(sql, connection)
connection.close()


data = temp_data


# add hour, month and day columns to dataframe
data['hour'] = data.date1.dt.hour
data['month'] = data.date1.dt.month
data['day'] = data.date1.dt.day


# group data by year
t_data = data.groupby(temp_data.date1.dt.year)


# add week column to data

group_list = []
all_weeks = 53


# add groups to a list to make it easier to work with (there are probably better ways than this)
i = 1991
while i <= 2021:
    group_list.append(t_data.get_group(i))
    i +=1

# get a 1 week interval for the same weeks in each year
week_list = []
week = 1
# for each week of a 'year', add the interval of all the years with that week to g_list, then append to week_list
while week <= all_weeks:
    g_list = []
    for i in group_list:
        g_list.append(i.iloc[24*7*(week-1):24*7*week])
    week_list.append(g_list)
    week += 1

# concatenate each of the week intervals
week_list = [pd.concat(i) for i in week_list]

# output: week_list -- list of week intervals (1-53) + date1, temp, week, hour


# concat all the weeks together
w_list = pd.concat(week_list)

w_list = w_list[['temp', 'week', 'hour', 'day', 'month']]


# get sample data for the percentile
f = w_list.groupby(['week', 'hour']).sample(214, replace=True)
f.sort_values(by=['month', 'day', 'hour'], inplace=True, ignore_index=True)


# obtain required values for the graph
n = len(w_list)
z_critical = stats.norm.ppf(q = 0.975)
p_mean = w_list.groupby(['month', 'week', 'day', 'hour']).mean()['temp'] # find means
p_std = w_list.groupby(['month', 'week', 'day', 'hour']).std()['temp'] # find standard deviations
p_se = scipy.stats.sem(p_mean) # standard error
mof = z_critical * (p_std/math.sqrt(n))
ci_lo = p_mean - mof # lower bracket of confidence interval
ci_hi = p_mean + mof # upper bracket of confidence interval
p_p90 = f.groupby(['month', 'week', 'day', 'hour']).quantile(0.1)['temp'] # find p90

p_mean = p_mean.reset_index() # reset index for p_mean

# convert dataframes to list
st = p_std.values.tolist()
hi = ci_hi.values.tolist()
lo = ci_lo.values.tolist()
p90 = p_p90.values.tolist()


# create new columns in p_mean and add values to them
p_mean['std'] = st
p_mean['ci_hi'] = hi
p_mean['ci_lo'] = lo
p_mean['p90'] = p90


m = p_mean

# create a date column with string values to use for the xaxis of the graph
m['date'] = m['month'].astype(str) + "-" + m['day'].astype(str) + " " + m['hour'].astype(str) + ":00"


# create the 'day_no' column and append to the dataframe
c = 0
l = []
for i in m['hour']:
    if i == 0:
        c += 1
        l.append(c)
    else:
        l.append(c)


# create new column in the dataframe
m['day_no'] = l


# create the figure
fig = go.Figure()
ci = 1.96 * np.std(m['temp'])/np.mean(m['temp'])

# create traces for different columns of the dataframe
# including: the mean, the confidence interval and the p90
mean_trace = [dict(visible=False,
                line=dict(width=2, color="blue"),
                mode='lines',
                name="temp",
                x=m.date[m['day_no'] == i],
                y=m.temp[m['day_no'] == i]) for i in range(1, 366)]

mean_trace2 = [dict(visible=False,
                line=dict(width=1, color="blue"),
                mode='lines',
                name="temp",
                x=m.date[m['day_no'] == i],
                y=m.temp[m['day_no'] == i],
                showlegend = False,
                hoverinfo='skip') for i in range(1, 366)]


ci_lower = [dict(visible=False,
                line=dict(width=0,color='darkgrey'),
                name="ci_lo",
                mode='lines',
                x=m.date[m['day_no'] == i],
                y=m.temp[m['day_no'] == i] - ci,
                fill='tonexty',
                fillcolor='rgba(68, 68, 68, 0.3)') for i in range(1, 366)]
                
ci_upper = [dict(
                visible=False,
                line=dict(width=0, color='grey'),
                name="ci_hi",
                mode='lines',
                x=m.date[m['day_no'] == i],
                y=m.temp[m['day_no'] == i] + ci,
                fill='tonexty',
                fillcolor='rgba(68, 68, 68, 0.3)') for i in range(1, 366)]
    
p90_trace = [dict(visible=False,
                line=dict(width=0, color='red'),
                mode='lines',
                name="p90",
                x=m.date[m['day_no'] == i],
                y=m.p90[m['day_no'] == i],
                fill='tonexty') for i in range(1, 366)]

all_m = mean_trace
all_m += ci_upper
all_m += mean_trace2
all_m += ci_lower
all_m += p90_trace


fig = go.Figure(data=all_m)


# make the traces visible on the first frame before the slider is touched
fig.data[0].visible = True
fig.data[365].visible = True
fig.data[365*3].visible = True
fig.data[365*2].visible = True
fig.data[365*4].visible = True



# set up sliders
weeks = []
for i in range(1, 365):
    week = dict(
        method="restyle",
        args=[{"visible": [False] * len(fig.data)},
              {"title": "week " + str(i)}],  # layout attribute
        label="day {}".format(i)
    )
    # makes all parts of the combined trace visible
    week["args"][0]["visible"][i] = True
    week["args"][0]["visible"][i+365] = True
    week["args"][0]["visible"][i+365*2] = True
    week["args"][0]["visible"][i+365*3] = True
    week["args"][0]["visible"][i+365*4] = True
    weeks.append(week)

# set up sliders some more (settings)
sliders = [dict(
    active=300,
    currentvalue={"prefix": "week: "},
    pad={"t": 20},
    steps=weeks
    
)]

# update graph with sliders
fig.update_layout(
    sliders=sliders,
    hovermode='x'
)


# convert figure to json
fig = json.dumps(fig, cls=plotly.utils.PlotlyJSONEncoder)

# print json fig to pass off to r
print(fig)