import streamlit as st
import pandas as pd
import numpy as np
import os
from PIL import Image
from util import dev_note

# - Expected Data: Multiple Connection Throughput and Latency. *Optional: Highlight string.

# - Format:

#     > Throughput = A table-like dataframe with columns like:

#     MsQuic Commit Sequence Number         | Windows+TCP/TLS | Linux+TCP/TLS | Windows+QUIC | Linux+QUIC
#     <github link>   | 5 HPS          | 4 HPS        | 5 HPS      | 4 HPS
#     ...             | 5 HPS          | 4 HPS        | 5 HPS      | 4 HPS
#     ...

#     > Latency = Similar to throughput table.

#     ...


EXAMPLE_GITHUB_COMMIT_LINKS = [f"https://example.com#{i}" for i in range(20)]

# Just fill with dummy data for now. Instantiate a dummy (20 x 5) dataframe with random data.
# TODO: Fetch this from an API or CDN or some blob somewhere instead of hard-coding...
HPS_DATA_SINGLE_CONN = pd.DataFrame({
    "MsQuic Commit Sequence Number": range(1, 21),
    "Windows+TCP/TLS": map(lambda x: round(x, ndigits=3), np.random.uniform(1.9, 3, 20)),
    "Linux+TCP/TLS": map(lambda x: round(x, ndigits=3), np.random.uniform(2.9, 5.1, 20)),
    "Windows+QUIC": map(lambda x: round(x, ndigits=3), np.random.uniform(3.9, 6.1, 20)),
    "Linux+QUIC": map(lambda x: round(x, ndigits=3), np.random.uniform(1.9, 4.1, 20)),
})

HPS_DATA_MULTI_CONN = pd.DataFrame({
    "MsQuic Commit Sequence Number": range(1, 21),
    "Windows+TCP/TLS": map(lambda x: round(x, ndigits=3), np.random.uniform(1.9, 3, 20)),
    "Linux+TCP/TLS": map(lambda x: round(x, ndigits=3), np.random.uniform(2.9, 5.1, 20)),
    "Windows+QUIC": map(lambda x: round(x, ndigits=3), np.random.uniform(3.9, 6.1, 20)),
    "Linux+QUIC": map(lambda x: round(x, ndigits=3), np.random.uniform(1.9, 4.1, 20)),
})

HIGHLIGHT_STRING = """
Did you know that you can get a lot more
HPS by enabling XDP?
"""


# ===================================================================================
# Code
# ===================================================================================



current_directory = os.path.dirname(os.path.abspath(__file__)) + "/../"
st.sidebar.image(Image.open(os.path.join(current_directory, "msft.png")), width=200)
st.sidebar.title("NetPerf Hightlight")
st.sidebar.text(HIGHLIGHT_STRING)
st.sidebar.button("Learn more")

st.title("Max Handshakes Per Second")
st.subheader("[Single Connection]")
st.text(f"Data as of the latest commit (Commit Sequence Number {len(HPS_DATA_SINGLE_CONN['MsQuic Commit Sequence Number'])})")

latest_windows_tcp_t =  HPS_DATA_SINGLE_CONN["Windows+TCP/TLS"][0]
latest_windows_quic_t =  HPS_DATA_SINGLE_CONN["Windows+QUIC"][0]
latest_linux_tcp_t =  HPS_DATA_SINGLE_CONN["Linux+TCP/TLS"][0]
latest_linux_quic_t =  HPS_DATA_SINGLE_CONN["Linux+QUIC"][0]

col0, col1, col2 = st.columns(3)
image_path = os.path.join(current_directory, "windows.png")
col0.image(Image.open(image_path), width=75, caption="Windows")
col1.metric("TCP/TLS (HPS measured in millions)", str(latest_windows_tcp_t) + " HPS", str(round(latest_windows_tcp_t - latest_linux_tcp_t, ndigits=3)) + " HPS")
col2.metric("QUIC", str(latest_windows_quic_t) + " HPS", str(round(latest_windows_quic_t - latest_linux_quic_t, ndigits=3)) + "HPS")

col0, col1, col2= st.columns(3)
image_path_linux = os.path.join(current_directory, "linux.png")
col0.image(Image.open(image_path_linux), width=75, caption="Linux")
col1.metric("TCP/TLS", str(latest_linux_tcp_t) + " HPS", str(round(-latest_windows_tcp_t + latest_linux_tcp_t, ndigits=3)) + " HPS")
col2.metric("QUIC", str(latest_linux_quic_t) + " HPS", str(round(-latest_windows_quic_t + latest_linux_quic_t, ndigits=3)) + "HPS")

st.line_chart(
    HPS_DATA_SINGLE_CONN, x="MsQuic Commit Sequence Number", y=["Windows+TCP/TLS", "Linux+TCP/TLS", "Windows+QUIC", "Linux+QUIC"],
    color=["#FF0000", "#0000FF",
           "#000000", "#00FF00"]
)



dev_note("The above line graph should be clickable. Clicking the graph will open a new tab to the commit itself on Github</span>")


st.subheader("[Multiple Connections (40)]")
st.text(f"Data as of the latest commit (Commit Sequence Number {len(HPS_DATA_MULTI_CONN['MsQuic Commit Sequence Number'])})")

latest_windows_tcp_t =  HPS_DATA_MULTI_CONN["Windows+TCP/TLS"][0]
latest_windows_quic_t =  HPS_DATA_MULTI_CONN["Windows+QUIC"][0]
latest_linux_tcp_t =  HPS_DATA_MULTI_CONN["Linux+TCP/TLS"][0]
latest_linux_quic_t =  HPS_DATA_MULTI_CONN["Linux+QUIC"][0]

col0, col1, col2 = st.columns(3)
image_path = os.path.join(current_directory, "windows.png")
col0.image(Image.open(image_path), width=75, caption="Windows")
col1.metric("TCP/TLS", str(latest_windows_tcp_t) + " HPS", str(round(latest_windows_tcp_t - latest_linux_tcp_t, ndigits=3)) + " HPS")
col2.metric("QUIC", str(latest_windows_quic_t) + " HPS", str(round(latest_windows_quic_t - latest_linux_quic_t, ndigits=3)) + "HPS")

col0, col1, col2= st.columns(3)
image_path_linux = os.path.join(current_directory, "linux.png")
col0.image(Image.open(image_path_linux), width=75, caption="Linux")
col1.metric("TCP/TLS", str(latest_linux_tcp_t) + " HPS", str(round(-latest_windows_tcp_t + latest_linux_tcp_t, ndigits=3)) + " HPS")
col2.metric("QUIC", str(latest_linux_quic_t) + " HPS", str(round(-latest_windows_quic_t + latest_linux_quic_t, ndigits=3)) + "HPS")

st.line_chart(
    HPS_DATA_MULTI_CONN, x="MsQuic Commit Sequence Number", y=["Windows+TCP/TLS", "Linux+TCP/TLS", "Windows+QUIC", "Linux+QUIC"],
    color=["#FF0000", "#0000FF",
           "#000000", "#00FF00"]
)
