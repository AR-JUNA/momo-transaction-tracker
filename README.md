# MoMo Transaction Analytics Dashboard

![Status](https://img.shields.io/badge/Status-In%20Progress-orange?style=flat-square)
![Python](https://img.shields.io/badge/Python-3.10+-blue?style=flat-square&logo=python)
![SQLite](https://img.shields.io/badge/Database-SQLite3-lightgrey?style=flat-square&logo=sqlite)

> A fullstack application that processes, categorizes, and visualizes MoMo (Mobile Money) SMS transaction data from XML format into an interactive dashboard.

## Table of Contents
- [About the Project](#about-the-project)
- [Team](#team)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Tech Stack](#tech-stack)
- [Scrum Board](#scrum-board)
- [Getting Started](#getting-started)

## About the Project

This project involves the design and development of an enterprise-level fullstack application focused on processing and analyzing MoMo (Mobile Money) SMS transaction data. The core objective is to transform raw MoMo SMS data, provided in XML format, into structured, actionable insights through a robust backend and an intuitive frontend interface.


The system will:
- Parse and clean the raw XML transaction data
- Categorize each transaction (payments, transfers, withdrawals, etc.)
- Store everything in a SQLite database
- Display the data on a frontend dashboard with charts and tables

We are currently in **Week 1 Team Setup and Planning**.

## Team

**Team Name:** Yellow

| Name | GitHub 
|------|--------
| Chigozie Ndubuaku Emmanuel | [@Chigozie-Nuel](https://github.com/Chigozie-Nuel) 
| Arjuna Caleb Gyan | [@AR-JUNA](https://github.com/AR-JUNA) 
| Maoulaika Mugeni | [@mmugeni](https://github.com/mmugeni)
| Lisette Mukiza | [@lisette-lachiever](https://github.com/lisette-lachiever) 


## Architecture 

The system is split into four layers that feed into each other:

```
[ XML Input ]
      |
      v
[ ETL Pipeline ]  -->  parse > clean > categorize > load
      |
      v
[ SQLite Database ]  +  dashboard.json (for frontend)
      |
      v
[ Frontend Dashboard ]  -->  charts + transaction table
```



## Project Structure

```
momo-dashboard/
│
├── README.md                    # What this project is and how to run it
├── .env.example                 # Example config file copy this and add your settings
├── requirements.txt             # Python libraries needed to run the project
├── index.html                   # The main page that opens in the browser
│
├── web/                         # Everything the user sees in the browser
│   ├── styles.css               # Makes the dashboard look good
│   ├── chart_handler.js         # Loads the data and draws the charts
│   └── assets/                  # Any images or icons used on the page
│
├── data/                        # All data the project uses or creates
│   ├── raw/                     # The original XML file goes here (not uploaded to GitHub)
│   │   └── momo.xml             # The raw MoMo SMS data we are working with
│   ├── processed/               # Clean data that the dashboard reads from
│   │   └── dashboard.json       # Summary of all transactions for the frontend
│   ├── db.sqlite3               # The database where all transactions are stored
│   └── logs/
│       ├── etl.log              # A record of what happened each time the pipeline ran
│       └── dead_letter/         # Messages that could not be read or processed
│
├── etl/                         # The backend scripts that process the data
│   ├── __init__.py              # Makes this folder a Python package
│   ├── config.py                # Settings like file paths and category rules
│   ├── parse_xml.py             # Reads the XML file and pulls out each transaction
│   ├── clean_normalize.py       # Fixes messy data formats amounts, dates, and phone numbers
│   ├── categorize.py            # Decides what type each transaction is (e.g. payment, transfer)
│   ├── load_db.py               # Saves the clean data into the database
│   └── run.py                   # Runs all the steps above in the correct order
│
├── api/                         # A simple API to access the data (bonus feature)
│   ├── __init__.py              # Makes this folder a Python package
│   ├── app.py                   # Sets up the API routes (/transactions, /analytics)
│   ├── db.py                    # Handles connecting to the database
│   └── schemas.py               # Defines the shape of the data the API returns
│
├── scripts/                     # Shortcuts to run common tasks
│   ├── run_etl.sh               # One command to run the full data pipeline
│   ├── export_json.sh           # Rebuilds the dashboard.json file from the database
│   └── serve_frontend.sh        # Starts a local server so you can view the dashboard
│
└── tests/                       # Checks that everything works correctly
    ├── test_parse_xml.py        # Tests that the XML is being read properly
    ├── test_clean_normalize.py  # Tests that the data cleaning works as expected
    └── test_categorize.py       # Tests that transactions are being categorized correctly
```

## Tech Stack

**Backend**
- Python 3.10+
- lxml / ElementTree - XML parsing
- python-dateutil - date normalization
- SQLite3 - database storage

**Frontend**
- HTML, CSS, Vanilla JavaScript
- Chart.js - data visualization

## Scrum Board

We are using GitHub Projects to manage our weekly tasks using Agile methodology.

Board: [https://github.com/users/mmugeni/projects/1](https://github.com/users/mmugeni/projects/1)

Columns: `To Do` | `In Progress` | `Done`

## Getting Started

> Full setup instructions will be added as the project develops. Below is the basic flow.

**1. Clone the repo**
```bash
git clone https://github.com/mmugeni/momo-dashboard.git
cd momo-dashboard
```

**2. Install dependencies**
```bash
pip install -r requirements.txt
```

**3. Run the ETL pipeline**
```bash
bash scripts/run_etl.sh
```

**4. Launch the dashboard**
```bash
bash scripts/serve_frontend.sh
# Open http://localhost:8000
```
