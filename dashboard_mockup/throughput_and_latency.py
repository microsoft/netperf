import streamlit as st
import pandas as pd
import numpy as np
import os
from PIL import Image
import webbrowser


# - Expected Data: Multiple Connection Throughput and Latency. *Optional: Highlight string.

# - Format:

#     > Throughput = A table-like dataframe with columns like:

#     MsQuic Commit Sequence Number         | Windows+TCP/TLS | Linux+TCP/TLS | Windows+QUIC | Linux+QUIC
#     <github link>   | 5 GB/s          | 4 GB/s        | 5 GB/s      | 4 GB/s
#     ...             | 5 GB/s          | 4 GB/s        | 5 GB/s      | 4 GB/s
#     ...

#     > Latency = Similar to throughput table.

#     ...


EXAMPLE_GITHUB_COMMIT_LINKS = [f"https://example.com#{i}" for i in range(20)]

# Just fill with dummy data for now. Instantiate a dummy (20 x 5) dataframe with random data.
# TODO: Fetch this from an API or CDN or some blob somewhere instead of hard-coding...
THROUGHPUT_DATA = pd.DataFrame({
    "MsQuic Commit Sequence Number": range(1, 21),
    "Windows+TCP/TLS": map(lambda x: round(x, ndigits=3), np.random.uniform(1.9, 3, 20)),
    "Linux+TCP/TLS": map(lambda x: round(x, ndigits=3), np.random.uniform(2.9, 5.1, 20)),
    "Windows+QUIC": map(lambda x: round(x, ndigits=3), np.random.uniform(3.9, 6.1, 20)),
    "Linux+QUIC": map(lambda x: round(x, ndigits=3), np.random.uniform(1.9, 4.1, 20)),
})

LATENCY_DATA = pd.DataFrame({
    "MsQuic Commit Sequence Number": range(1, 21),
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



current_directory = os.path.dirname(os.path.abspath(__file__))
st.sidebar.image(Image.open(os.path.join(current_directory, "msft.png")), width=200)
st.sidebar.title("NetPerf Hightlight")
st.sidebar.text(HIGHLIGHT_STRING)
st.sidebar.button("Learn more")

st.header("Single Connection")
st.subheader("Throughput Comparison [Higher is better]")
st.text(f"Data as of the latest commit (Commit Sequence Number {len(THROUGHPUT_DATA['MsQuic Commit Sequence Number'])})")

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
    THROUGHPUT_DATA, x="MsQuic Commit Sequence Number", y=["Windows+TCP/TLS", "Linux+TCP/TLS", "Windows+QUIC", "Linux+QUIC"],
    color=["#FF0000", "#0000FF",
           "#000000", "#00FF00"]
)

highlighted_idx = st.number_input("Find A Commit By Sequence Number", min_value=1, max_value=20, value=1)
if st.button("Find Commit"):
    webbrowser.open(EXAMPLE_GITHUB_COMMIT_LINKS[highlighted_idx - 1])

st.subheader("Latency Comparison [Lower is better]")
st.text(f"Data as of the latest commit (Commit Sequence Number {len(LATENCY_DATA['MsQuic Commit Sequence Number'])})")

p50, p90, p95 = st.columns(3)

p50_clicked = p50.button("View 50th Percentile")
p90_clicked = p90.button("View 90th Percentile")
p95_clicked = p95.button("View 95th Percentile")

curr_percentile = "90th percentile"

if p50_clicked:
    curr_percentile = "50th percentile"
elif p90_clicked:
    curr_percentile = "90th percentile"
elif p95_clicked:
    curr_percentile = "95th percentile"

st.write(curr_percentile)

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
    LATENCY_DATA, x="MsQuic Commit Sequence Number", y=["Windows+TCP/TLS", "Linux+TCP/TLS", "Windows+QUIC", "Linux+QUIC"],
    color=["#FF0000", "#0000FF",
           "#000000", "#00FF00"]
)
