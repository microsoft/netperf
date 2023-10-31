from util import dev_note

import streamlit as st

dev_note("We still need to figure out whether to only display throughput data on the latest commit, or past N commits.")

# Define a function to simulate data retrieval for the metrics
def get_metric_data(metric_name):
    # Simulate data retrieval here (you would replace this with actual data)
    # Return data for the given metric name
    # For example, return a dictionary with 'alternative_name' and 'value'
    data = {
        'Alternative 1': 100,  # Replace with actual data
        'Alternative 2': 120,  # Replace with actual data
        'Alternative 3': 80,   # Replace with actual data
    }
    return data

# Create a Streamlit app
st.title("AF_XDP vs. Alternatives Metrics Dashboard")

# Create dropdowns for selecting metrics
selected_metric = st.selectbox("Select Metric", [
    "AF_XDP bulk throughput",
    "AF_XDP small throughput",
    "AF_XDP bulk latency",
    "AF_XDP small latency",
    "AF_XDP bursty latency",
    "Offload X performance improvement",
    "XDP inspection overhead",
    "DDoS packet inspection and drop rate",
    "Packet inspection and forwarding rate",
])

# Define the metric name for data retrieval
metric_name = selected_metric.lower()

# Get data for the selected metric
metric_data = get_metric_data(metric_name)

# Create a bar chart to compare the metrics
st.bar_chart(metric_data)

# Display the metric values for different alternatives
st.write("Metric Comparison for Different Alternatives:")
for alternative, value in metric_data.items():
    st.write(f"{alternative}: {value}")

# TODO: Add more components and functionality as needed for your specific use case

# Run the Streamlit app
if __name__ == "__main__":
    st.write("This is a simple Streamlit dashboard for comparing AF_XDP metrics to alternatives.")
    st.write("You can select a metric from the dropdown and view the comparison for different alternatives.")
