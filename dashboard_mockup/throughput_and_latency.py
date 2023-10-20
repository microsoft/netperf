import streamlit as st
import pandas as pd
import numpy as np
from datetime import datetime

st.sidebar.image("msft.png", width=200)
st.sidebar.title("NetPerf Hightlight")
st.sidebar.text("""
 Did you know that Windows + TCP/TLS is
 5-10% faster than Linux + TCP/TLS?""")
st.sidebar.button("Learn more")

st.header("Throughput Comparison [Higher is better]")
# hide_img_fs = '''
# <style>
# button[title="View fullscreen"]{
#     visibility: hidden;}
# </style>
# '''
# st.markdown(hide_img_fs, unsafe_allow_html=True)
st.text("Data as of July 2023")

# st.subheader("With Windows:")
col0, col1, col2, col3, col4 = st.columns(5)
col0.image("windows.png", width=75)
col1.metric("TCP/TLS \n \n Single Connection", "5 GB/s", "1 Gb/s")
col2.metric("TCP/TLS \n \n Muliple Connections", "5 GB/s", "1 Gb/s")
col3.metric("QUIC \n \n Single Connection", "5 GB/s", "-1 Gb/s")
col4.metric("QUIC \n \n Multiple Connections", "5 GB/s", "1 Gb/s")

# st.subheader("With Linux:")
col0, col1, col2, col3, col4 = st.columns(5)
col0.image("linux.png", width=75)
col1.metric("TCP/TLS \n \n Single Connection", "4 GB/s", "-1 Gb/s")
col2.metric("TCP/TLS \n \n Muliple Connections", "4 GB/s", "-1 Gb/s")
col3.metric("QUIC \n \n Single Connection", "6 GB/s", "1 Gb/s")
col4.metric("QUIC \n \n Multiple Connections", "4 GB/s", "-1 Gb/s")


# Generate a list of string dates
date_strings = ["2023-10-01", "2023-10-02", "2023-10-03", "2023-10-04", "2023-10-05",
                "2023-10-06", "2023-10-07", "2023-10-08", "2023-10-09", "2023-10-10",
                "2023-10-11", "2023-10-12", "2023-10-13", "2023-10-14", "2023-10-15",
                "2023-10-16", "2023-10-17", "2023-10-18", "2023-10-19", "2023-10-20"]

# Create a DataFrame with the list of dates and random data
chart_data = pd.DataFrame({
    "Date": date_strings,
    "Windows+TCP/TLS": np.random.uniform(1.9, 3, 20),
    "Linux+TCP/TLS": np.random.uniform(2.9, 5.1, 20),
    "Windows+QUIC": np.random.uniform(3.9, 6.1, 20),
    "Linux+QUIC": np.random.uniform(1.9, 4.1, 20),
})

chart_data["Date"] = chart_data["Date"].apply(lambda x: datetime.strptime(x, "%Y-%m-%d"))
toggled = st.toggle("Throughput For Multiple Connections")
# Create the line chart
st.line_chart(
    chart_data, x="Date", y=["Windows+TCP/TLS", "Linux+TCP/TLS", "Windows+QUIC", "Linux+QUIC"],
    color=["#FF0000", "#0000FF",
           "#000000", "#00FF00"]
)


st.header("Latency Comparison [Lower is better]")


# st.subheader("With Windows:")
col0, col1, col2, col3, col4 = st.columns(5)
col0.image("windows.png", width=75)
col1.metric("TCP/TLS \n \n Single Connection", "5 ns", "1 ns", delta_color="inverse")
col2.metric("TCP/TLS \n \n Muliple Connections", "5 ns", "1 ns", delta_color="inverse")
col3.metric("QUIC \n \n Single Connection", "5 ns", "-1 ns", delta_color="inverse")
col4.metric("QUIC \n \n Multiple Connections", "5 ns", "1 ns", delta_color="inverse")

# st.subheader("With Linux:")
col0, col1, col2, col3, col4 = st.columns(5)
col0.image("linux.png", width=75)
col1.metric("TCP/TLS \n \n Single Connection", "4 ns", "-1 ns", delta_color="inverse")
col2.metric("TCP/TLS \n \n Muliple Connections", "4 ns", "-1 ns", delta_color="inverse")
col3.metric("QUIC \n \n Single Connection", "6 ns", "1 ns", delta_color="inverse")
col4.metric("QUIC \n \n Multiple Connections", "4 ns", "-1 ns", delta_color="inverse")



# Generate a list of string dates
date_strings = ["2023-10-01", "2023-10-02", "2023-10-03", "2023-10-04", "2023-10-05",
                "2023-10-06", "2023-10-07", "2023-10-08", "2023-10-09", "2023-10-10",
                "2023-10-11", "2023-10-12", "2023-10-13", "2023-10-14", "2023-10-15",
                "2023-10-16", "2023-10-17", "2023-10-18", "2023-10-19", "2023-10-20"]

# Create a DataFrame with the list of dates and random data
chart_data = pd.DataFrame({
    "Date": date_strings,
    "Windows+TCP/TLS": np.random.uniform(1.9, 3, 20),
    "Linux+TCP/TLS": np.random.uniform(2.9, 5.1, 20),
    "Windows+QUIC": np.random.uniform(3.9, 6.1, 20),
    "Linux+QUIC": np.random.uniform(1.9, 4.1, 20),
})

chart_data["Date"] = chart_data["Date"].apply(lambda x: datetime.strptime(x, "%Y-%m-%d"))
st.toggle("Latency For Multiple Connections")
# Create the line chart
st.line_chart(
    chart_data, x="Date", y=["Windows+TCP/TLS", "Linux+TCP/TLS", "Windows+QUIC", "Linux+QUIC"],
    color=["#FF0000", "#0000FF",
           "#000000", "#00FF00"]
)
