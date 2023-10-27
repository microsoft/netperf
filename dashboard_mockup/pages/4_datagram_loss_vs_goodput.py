import streamlit as st
from util import dev_note
import pandas as pd

st.title("Datagram Loss vs Goodput")

st.subheader("[Single Connection]")

dev_note("We graph loss and goodput for some commit (latest commit), and let the user choose the commit from a dropdown or something.")

dev_note("In addition, the user can choose multiple commits to graph, and it will show all of them in a single graph, to see which is better")

dev_note("Datagram loss is measured in terms of 0 to 1. 0 means no loss (perfect network)")
# ==================================================================================
# Data
# ==================================================================================

EXAMPLE_DATA_1 = {
    "commit" : ["example commit hash 1"]*3,
    "losses" : [0, 0.5, 0.9],
    "goodput" : [1000, 500, 400]
}


EXAMPLE_DATA_2 = {
    "commit" : ["example commit hash 2"]*3,
    "losses" : [0, 0.5, 0.9],
    "goodput" : [900, 450, 200]
}


EXAMPLE_DATA_3 = {
    "commit" : ["example commit hash 3"]*3,
    "losses" : [0, 0.5, 0.9],
    "goodput" : [1200, 800, 300]
}


# ===================================================================================
# Code
# ===================================================================================

combine = {}
combine["losses"] = EXAMPLE_DATA_1["losses"] + EXAMPLE_DATA_2["losses"] + EXAMPLE_DATA_3["losses"]
combine["commit"] = EXAMPLE_DATA_1["commit"] + EXAMPLE_DATA_2["commit"] + EXAMPLE_DATA_3["commit"]
combine["goodput"] = EXAMPLE_DATA_1["goodput"] + EXAMPLE_DATA_2["goodput"] + EXAMPLE_DATA_3["goodput"]

st.line_chart(pd.DataFrame(combine), x="losses", y="goodput", color="commit")

st.subheader("[Multiple Connections (40)]")

combine = {}
EXAMPLE_DATA_1["goodput"] = [9000, 457, 400]
EXAMPLE_DATA_2["goodput"] = [500, 450, 200]
EXAMPLE_DATA_3["goodput"] = [1000, 800, 300]

combine["losses"] = EXAMPLE_DATA_1["losses"] + EXAMPLE_DATA_2["losses"] + EXAMPLE_DATA_3["losses"]
combine["commit"] = EXAMPLE_DATA_1["commit"] + EXAMPLE_DATA_2["commit"] + EXAMPLE_DATA_3["commit"]
combine["goodput"] = EXAMPLE_DATA_1["goodput"] + EXAMPLE_DATA_2["goodput"] + EXAMPLE_DATA_3["goodput"]

st.line_chart(pd.DataFrame(combine), x="losses", y="goodput", color="commit")
