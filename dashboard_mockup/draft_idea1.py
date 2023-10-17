import streamlit as st
import pandas as pd
import numpy as np

chart_data = pd.DataFrame(np.random.rand(20, 3), columns=["Release", "Windows", "Linux"])

st.title("Draft Idea #1")

st.write("""

Here, we showcase some capabilities of Streamlit to render graphs,
to see how well they fit our use case, and to pick the most illustrative graphs
for our final dashboard. Random data is used.

""")

st.subheader("Line Chart - Great for showing improvements to latency over Windows releases?")

st.line_chart(
   chart_data, x="Release", y=["Windows", "Linux"], color=["#FF0000", "#0000FF"]  # Optional
)

st.subheader("Area Chart - Probably not helpful for us but its cool?")

chart_data = pd.DataFrame(np.random.randn(20, 3), columns=["XDP", "DPTK", "No XDP / DPTK"])

st.area_chart(chart_data)


st.subheader("Bar Chart - Great for showing how great X is over Y? Or breakdown of work done?")

chart_data = pd.DataFrame(
   {
       "Connections": list(range(20)) * 3,
       "CPU_Stress": np.random.rand(60),
       "Work_Distribution": ["Handshakes"] * 20 + ["Sending Data"] * 20 + ["Receiving Data"] * 20,
   }
)

st.bar_chart(chart_data, x="Connections", y="CPU_Stress", color="Work_Distribution")


st.subheader("Graph Viz Chart -- Great for showing the DAG of a test if a partner has questions?")

st.graphviz_chart('''
    digraph {
        run -> intr
        intr -> runbl
        runbl -> run
        run -> kernel
        kernel -> zombie
        kernel -> sleep
        kernel -> runmem
        sleep -> swap
        swap -> runswap
        runswap -> new
        runswap -> runmem
        new -> runmem
        sleep -> runmem
    }
''')
