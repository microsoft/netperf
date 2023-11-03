import streamlit as st
import streamlit as st
import pandas as pd
import matplotlib.pyplot as plt
from util import dev_note

st.title("Network Performance Today")

# Create dummy data
DOWNLOAD_DATA = {
    'Operating System': ['Windows <build / version>', 'Windows <build / version>', 'Linux<build / version>', 'Linux<build / version>'],
    'Protocol': ['TCP', 'QUIC', 'TCP', 'QUIC'],
    'GB/s': [50, 60, 30, 40]
}

UPLOAD_DATA = {
    'Operating System': ['Windows <build / version>', 'Windows <build / version>', 'Linux<build / version>', 'Linux<build / version>'],
    'Protocol': ['TCP', 'QUIC', 'TCP', 'QUIC'],
    'GB/s': [55, 66, 33, 54]
}

RPS_DATA = {
    'Operating System': ['Windows <build / version>', 'Windows <build / version>', 'Linux<build / version>', 'Linux<build / version>'],
    'Protocol': ['TCP', 'QUIC', 'TCP', 'QUIC'],
    'GB/s': [5000, 8000, 4000, 6000]
}

LATENCY_DATA = {
    'Operating System': ['Windows <build / version>', 'Windows <build / version>', 'Linux<build / version>', 'Linux<build / version>'],
    'Protocol': ['TCP', 'QUIC', 'TCP', 'QUIC'],
    'GB/s': [12, 8, 5, 4]
}

def make_chart(data, mnt, xlabel, ylabel, title):
    df = pd.DataFrame(data)

    # Filter data for TCP and QUIC
    tcp_data = df[df['Protocol'] == 'TCP']
    quic_data = df[df['Protocol'] == 'QUIC']

    fig, ax = plt.subplots()

    # Bar width for each pair
    bar_width = 0.35
    index = range(len(tcp_data))

    # Create bars for TCP
    ax.bar([i - bar_width/2 for i in index], tcp_data['GB/s'], bar_width, label='TCP', color='blue')

    # Create bars for QUIC
    ax.bar([i + bar_width/2 for i in index], quic_data['GB/s'], bar_width, label='QUIC', color='green')

    # Set the X-axis labels to Operating Systems
    ax.set_xticks(index)
    ax.set_xticklabels(tcp_data[xlabel])
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.set_title(title)

    # Display the legend
    ax.legend()

    # Show the bar chart
    mnt.pyplot(fig)

dev_note("In the production app, the latency chart should periodically update itself with new data to reflect P50, P90, and P99 latencies.")

col0, col1 = st.columns(2)

make_chart(DOWNLOAD_DATA, col0, 'Operating System', 'GB/s', 'Download Throughput Comparison')
make_chart(UPLOAD_DATA, col1, 'Operating System', 'GB/s', 'Upload Throughput Comparison')

col2, col3 = st.columns(2)

make_chart(RPS_DATA, col2, 'Operating System', 'RPS', 'Requests Per Second Comparison')
make_chart(LATENCY_DATA, col3, 'Operating System', 'ns', 'P90 Latency Comparison')

dev_note("We also wanna make these bar charts bigger and look more professional.")