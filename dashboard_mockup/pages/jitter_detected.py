import streamlit as st
import pandas as pd
import numpy as np

chart_data = pd.DataFrame(
   {
       "col1": range(20),
       "col2": np.random.randn(20),
   }
)

st.line_chart(chart_data, x="col1", y="col2")