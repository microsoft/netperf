import streamlit as st
import pandas as pd
import numpy as np
import os
from PIL import Image



# - Expected Data: Single Connection Throughput and Latency. *Optional: Highlight string.

# - Format:

#     > Throughput = A table-like dataframe with columns like:

#     Date         | Windows+TCP/TLS | Linux+TCP/TLS | Windows+QUIC | Linux+QUIC
#     2023-10-01   | 5 GB/s          | 4 GB/s        | 5 GB/s      | 4 GB/s
#     2023-10-02   | 5 GB/s          | 4 GB/s        | 5 GB/s      | 4 GB/s
#     ...

#     > Latency = A table-like dataframe with columns like:

#     Date         | Windows+TCP/TLS | Linux+TCP/TLS | Windows+QUIC | Linux+QUIC
#     2023-10-01   | 1 ns            | 1 ns          | 1 ns        | 1 ns
#     2023-10-02   | 1 ns            | 1 ns          | 1 ns        | 1 ns
#     ...


# Just fill with dummy data for now. Instantiate a dummy (20 x 5) dataframe with random data.
# TODO: Fetch this from an API or CDN or some blob somewhere instead of hard-coding...
THROUGHPUT_DATA = pd.DataFrame({
    "Date": ["2023-10-01", "2023-10-02", "2023-10-03", "2023-10-04", "2023-10-05",
             "2023-10-06", "2023-10-07", "2023-10-08", "2023-10-09", "2023-10-10",
             "2023-10-11", "2023-10-12", "2023-10-13", "2023-10-14", "2023-10-15",
             "2023-10-16", "2023-10-17", "2023-10-18", "2023-10-19", "2023-10-20"],
    "Windows+TCP/TLS": map(lambda x: round(x, ndigits=3), np.random.uniform(1.9, 3, 20)),
    "Linux+TCP/TLS": map(lambda x: round(x, ndigits=3), np.random.uniform(2.9, 5.1, 20)),
    "Windows+QUIC": map(lambda x: round(x, ndigits=3), np.random.uniform(3.9, 6.1, 20)),
    "Linux+QUIC": map(lambda x: round(x, ndigits=3), np.random.uniform(1.9, 4.1, 20)),
})

LATENCY_DATA = pd.DataFrame({
    "Date": ["2023-10-01", "2023-10-02", "2023-10-03", "2023-10-04", "2023-10-05",
             "2023-10-06", "2023-10-07", "2023-10-08", "2023-10-09", "2023-10-10",
             "2023-10-11", "2023-10-12", "2023-10-13", "2023-10-14", "2023-10-15",
             "2023-10-16", "2023-10-17", "2023-10-18", "2023-10-19", "2023-10-20"],
    "Windows+TCP/TLS": map(lambda x: round(x, ndigits=3), np.random.uniform(1.9, 3, 20)),
    "Linux+TCP/TLS": map(lambda x: round(x, ndigits=3), np.random.uniform(2.9, 5.1, 20)),
    "Windows+QUIC": map(lambda x: round(x, ndigits=3), np.random.uniform(3.9, 6.1, 20)),
    "Linux+QUIC": map(lambda x: round(x, ndigits=3), np.random.uniform(1.9, 4.1, 20)),
})

HIGHLIGHT_STRING = """
Did you know that Windows + TCP/TLS is
5-10% faster than Linux + TCP/TLS?
"""


# ===================================================================================
# Code
# ===================================================================================



current_directory = os.path.dirname(os.path.abspath(__file__)) + "/../"
st.sidebar.image(Image.open(os.path.join(current_directory, "msft.png")), width=200)
st.sidebar.title("NetPerf Hightlight")
st.sidebar.text(HIGHLIGHT_STRING)
st.sidebar.button("Learn more")

# DATA:


st.header("Multiple Connections")
st.subheader("Throughput Comparison [Higher is better]")
st.text("Data as of " + THROUGHPUT_DATA["Date"][0])

latest_windows_tcp_t =  THROUGHPUT_DATA["Windows+TCP/TLS"][0]
latest_windows_quic_t =  THROUGHPUT_DATA["Windows+QUIC"][0]
latest_linux_tcp_t =  THROUGHPUT_DATA["Linux+TCP/TLS"][0]
latest_linux_quic_t =  THROUGHPUT_DATA["Linux+QUIC"][0]

col0, col1, col2 = st.columns(3)
image_path = os.path.join(current_directory, "windows.png")
col0.image(Image.open(image_path), width=75, caption="Windows")
col1.metric("TCP/TLS", str(latest_windows_tcp_t) + " GB/s", str(round(latest_windows_tcp_t - latest_linux_tcp_t, ndigits=3)) + " Gb/s")
col2.metric("QUIC", str(latest_windows_quic_t) + " GB/s", str(round(latest_windows_quic_t - latest_linux_quic_t, ndigits=3)) + "GB/s")

col0, col1, col2= st.columns(3)
image_path_linux = os.path.join(current_directory, "linux.png")
col0.image(Image.open(image_path_linux), width=75, caption="Linux")
col1.metric("TCP/TLS", str(latest_linux_tcp_t) + " GB/s", str(round(-latest_windows_tcp_t + latest_linux_tcp_t, ndigits=3)) + " Gb/s")
col2.metric("QUIC", str(latest_linux_quic_t) + " GB/s", str(round(-latest_windows_quic_t + latest_linux_quic_t, ndigits=3)) + "GB/s")


st.line_chart(
    THROUGHPUT_DATA, x="Date", y=["Windows+TCP/TLS", "Linux+TCP/TLS", "Windows+QUIC", "Linux+QUIC"],
    color=["#FF0000", "#0000FF",
           "#000000", "#00FF00"]
)


st.subheader("Latency Comparison [Lower is better]")
st.text("Data as of " + LATENCY_DATA["Date"][0])
latest_windows_tcp_l =  LATENCY_DATA["Windows+TCP/TLS"][0]
latest_windows_quic_l =  LATENCY_DATA["Windows+QUIC"][0]
latest_linux_tcp_l =  LATENCY_DATA["Linux+TCP/TLS"][0]
latest_linux_quic_l =  LATENCY_DATA["Linux+QUIC"][0]

col0, col1, col2 = st.columns(3)
image_path = os.path.join(current_directory, "windows.png")
col0.image(Image.open(image_path), width=75, caption="Windows")
col1.metric("TCP/TLS", str(latest_windows_tcp_l) + " ns", str(round(latest_windows_tcp_l - latest_linux_tcp_l, ndigits=3)) + " ns", delta_color="inverse")
col2.metric("QUIC", str(latest_windows_quic_l) + " ns", str(round(latest_windows_quic_l - latest_linux_quic_l, ndigits=3)) + "ns", delta_color="inverse")

col0, col1, col2= st.columns(3)
image_path_linux = os.path.join(current_directory, "linux.png")
col0.image(Image.open(image_path_linux), width=75, caption="Linux")
col1.metric("TCP/TLS", str(latest_linux_tcp_l) + " ns", str(round(-latest_windows_tcp_l + latest_linux_tcp_l, ndigits=3)) + " ns", delta_color="inverse")
col2.metric("QUIC", str(latest_linux_quic_l) + " ns", str(round(-latest_windows_quic_l + latest_linux_quic_l, ndigits=3)) + "ns", delta_color="inverse")


st.line_chart(
    LATENCY_DATA, x="Date", y=["Windows+TCP/TLS", "Linux+TCP/TLS", "Windows+QUIC", "Linux+QUIC"],
    color=["#FF0000", "#0000FF",
           "#000000", "#00FF00"]
)
