import streamlit as st
import pandas as pd
import numpy as np

st.sidebar.image("msft.png", width=200)
st.sidebar.title("NetPerf Hightlight")
st.sidebar.text("""
 Did you know that Windows + TCP/TLS is
 5-10% faster than Linux + TCP/TLS?""")
st.sidebar.button("Learn more")

st.header("Throughput Comparison [Higher is better]")

st.subheader("With TCP/TLS")

chart_data = pd.DataFrame(
   {
       "Date": ["Windows", "Linux"],
       "GB_Per_Second": np.random.rand(2),
       "Color": ["#FF0000", "#0000FF"],
   }
)

st.bar_chart(chart_data, x="Date", y="GB_Per_Second", color="Color")

st.header("Latency Comparison [Lower is better]")

