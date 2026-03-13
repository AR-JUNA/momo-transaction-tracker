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
| Chigozie | [@Chigozie-Nuel](https://github.com/Chigozie-Nuel) 
| Gyann | [@AR-JUNA](https://github.com/AR-JUNA) 
| Maoulaika | [@mmugeni](https://github.com/mmugeni)
| Lisette | [@lisette-lachiever](https://github.com/lisette-lachiever) 


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

Full diagram: [Add Link here](Link)

## Project Structure

```
momo-dashboard/
├── README.md
├── .env.example
├── requirements.txt
├── index.html
├── web/
│   ├── styles.css
│   ├── chart_handler.js
│   └── assets/
├── data/
│   ├── raw/            # momo.xml goes here (git-ignored)
│   ├── processed/      # dashboard.json output
│   └── logs/
├── etl/
│   ├── parse_xml.py
│   ├── clean_normalize.py
│   ├── categorize.py
│   ├── load_db.py
│   └── run.py
├── scripts/
│   ├── run_etl.sh
│   └── serve_frontend.sh
└── tests/
    ├── test_parse_xml.py
    ├── test_clean_normalize.py
    └── test_categorize.py
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
