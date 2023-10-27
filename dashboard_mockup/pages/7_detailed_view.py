import streamlit as st
from util import dev_note

st.title("Detailed View")

dev_note("""
         To pinpoint exactly what a visitor might be searching for,
         we have a detailed form the user fills out, and graph the results.
         """)

dev_note("""
The way its going to work is, the user can fill out the form any number of times
         to produce a new graph, and we enable them the ability to combine graphs for comparisons.
""")

dev_note("""
 For example, say we want to compare Linux vs. Windows on OpenSSL in terms of latency using
         the QUIC protocol. The user would just fill out the form twice, specifying those parameters,
         and combine their graphs to compare / contrast the results. They can fill it out again to
         make a third graph if they wanna see the throughput as well.
""")
