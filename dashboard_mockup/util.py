import streamlit as st

def dev_note(note):
    st.markdown(f"<span style='color:red'> // DEV NOTE: {note}", unsafe_allow_html=True)