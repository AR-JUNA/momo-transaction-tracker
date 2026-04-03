# MoMo Transaction Analytics Dashboard

![Status](https://img.shields.io/badge/Status-In%20Progress-orange?style=flat-square)
![Python](https://img.shields.io/badge/Python-3.10+-blue?style=flat-square&logo=python)
![MySQL](https://img.shields.io/badge/Database-MySQL%208.0-blue?style=flat-square&logo=mysql)
![API](https://img.shields.io/badge/API-REST%20%7C%20Basic%20Auth-purple?style=flat-square)

> A fullstack application that processes, categorizes, and visualizes MoMo (Mobile Money) SMS transaction data from XML format into an interactive dashboard.

## Table of Contents
- [About the Project](#about-the-project)
- [Team](#team)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Database Design](#database-design)
- [REST API](#rest-api)
- [Tech Stack](#tech-stack)
- [Scrum Board](#scrum-board)
- [Getting Started](#getting-started)

## About the Project

This project involves the design and development of an enterprise-level fullstack application focused on processing and analyzing MoMo (Mobile Money) SMS transaction data. The core objective is to transform raw MoMo SMS data, provided in XML format, into structured, actionable insights through a robust backend and an intuitive frontend interface.

The system will:
- Parse and clean the raw XML transaction data
- Categorize each transaction (payments, transfers, withdrawals, etc.)
- Store everything in a MySQL database
- Expose the data through a secured REST API with full CRUD support
- Display the data on a frontend dashboard with charts and tables

We are currently in **Week 4Building and Securing a REST API**.

## Team

**Team Name:** Yellow

| Name | GitHub |
|------|--------|
| Chigozie Ndubuaku Emmanuel | [@Chigozie-Nuel](https://github.com/Chigozie-Nuel) |
| Gyann Caleb | [@AR-JUNA](https://github.com/AR-JUNA) |
| Moulaika Mugeni | [@mmugeni](https://github.com/mmugeni) |
| Lisette Mukiza | [@lisette-lachiever](https://github.com/lisette-lachiever) |

## Architecture

The system is split into four layers that feed into each other:

```
[ XML Input ]
      |
      v
[ ETL Pipeline ]  -->  parse > clean > categorize > load
      |
      v
[ MySQL Database ]  +  dashboard.json (for frontend)
      |
      v
[ REST API ]  -->  /transactions  /health  /stats  (Week 4)
      |
      v
[ Frontend Dashboard ]  -->  charts + transaction table
```

## Project Structure

```
momo-dashboard/
│
├── README.md                      # What this project is and how to run it
├── .env.example                   # Example config filecopy this and add your settings
├── requirements.txt               # Python libraries needed to run the project
├── modified_sms_v2.xml            # Source SMS data (Week 4place in project root)
├── index.html                     # The main page that opens in the browser
│
├── docs/                          # Project documentation
│   ├── erd_diagram.png            # Entity Relationship Diagram for the database 
│   └── api_docs.md                # Full REST API reference with curl examples 
│
├── database/                      # Database setup files (Week 2)
│   └── database_setup.sql         # Creates all tables, adds sample data and CRUD queries
│
├── examples/                      # Example data formats (Week 2)
│   └── json_schemas.json          # Shows how each database table looks as a JSON API response
│
├── api/                           # REST API server (Week 4)
│   ├── __init__.py
│   └── server.py                     # Full CRUD API with Basic Authrun this to start the server
│
├── etl/                           # The backend scripts that process the data
│   ├── __init__.py                # Makes this folder a Python package
│   ├── config.py                  # Settings like file paths and category rules
│   ├── parse_xml.py               # Reads the XML file and pulls out each transaction 
│   ├── clean_normalize.py         # Fixes messy data formats amounts, dates, and phone numbers
│   ├── categorize.py              # Decides what type each transaction is (e.g. payment, transfer)
│   ├── load_db.py                 # Saves the clean data into the database
│   └── run.py                     # Runs all the steps above in the correct order
│
├── dsa/                           # Data Structures and Algorithms
│   ├── __init__.py
│   ├── parse_xml.py               # Tests that the XML is being read properly
│   └── dsa_search.py              # Linear Search vs Dictionary Lookup benchmark
│
├── tests/                         # Checks that everything works correctly
│   ├── api.http                   # VS Code REST Client test fileall endpoints 
│   ├── test_clean_normalize.py    # Tests that the data cleaning works as expected
│   └── test_categorize.py         # Tests that transactions are being categorized correctly
│
├── screenshots/                   # curl and terminal screenshots for the Week 4 report
│
├── web/                           # Everything the user sees in the browser
│   ├── styles.css                 # Makes the dashboard look good
│   ├── chart_handler.js           # Loads the data and draws the charts
│   └── assets/                    # Any images or icons used on the page
│
├── data/                          # All data the project uses or creates
│   ├── raw/                       # The original XML file goes here (not uploaded to GitHub)
│   │   └── momo.xml               # The raw MoMo SMS data we are working with
│   ├── processed/                 # Clean data that the dashboard reads from
│   │   └── dashboard.json         # Summary of all transactions for the frontend
│   ├── transactions.json          # Auto-generated cache after the API parses the XML
│   ├── db.sqlite3                 # The database where all transactions are stored
│   └── logs/
│       ├── etl.log                # A record of what happened each time the pipeline ran
│       └── dead_letter/           # Messages that could not be read or processed
│
└── scripts/                       # Shortcuts to run common tasks
    ├── run_etl.sh                 # One command to run the full data pipeline
    ├── export_json.sh             # Rebuilds the dashboard.json file from the database
    └── serve_frontend.sh          # Starts a local server so you can view the dashboard
```

## Database Design

In Week 2 we designed and implemented the MySQL database that stores all MoMo transaction data. The ERD was created using dbdiagram.io and is saved in `docs/erd_diagram.pdf`.

The database has **10 tables** covering every entity in the system.

| Table | What it stores |
|-------|---------------|
| `users` | Everyone in the systemcustomers, agents and merchants |
| `wallets` | Each user's balance and daily limit (1 wallet per user) |
| `agents` | MoMo agents who handle cash deposits and withdrawals |
| `merchants` | Businesses that accept MoMo payments |
| `transaction_categories` | The 10 transaction types (DEPOSIT, WITHDRAWAL, PEER_TRANSFER etc) |
| `sms_raw_messages` | Every SMS received, whether it parsed successfully or not |
| `transactions` | Every MoMo transactionthe main table |
| `tags` | Labels like "high-value" or "flagged" applied to transactions |
| `transaction_tags` | Junction tableconnects transactions to tags (many-to-many) |
| `system_logs` | Full audit trail of everything the ETL pipeline does |

The `examples/json_schemas.json` file shows how each table maps to a JSON object in the API, including fully nested transaction examples and a SQL-to-JSON mapping table.



## REST API

>The API is built in plain Python using `http.server`no external frameworks.

The API parses `modified_sms_v2.xml` (1,606 transactions) and exposes them through five CRUD endpoints protected by HTTP Basic Authentication. All changes made through the APIadds, updates, and deletesare saved to `data/transactions.json` and survive server restarts.

### Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/transactions` | List all transactionspaginated, filterable by type |
| `GET` | `/transactions/{id}` | Get one transaction by ID |
| `POST` | `/transactions` | Add a new transaction |
| `PUT` | `/transactions/{id}` | Update an existing transaction |
| `DELETE` | `/transactions/{id}` | Delete a transaction |
| `GET` | `/health` | Server status and uptime |
| `GET` | `/stats` | Request counts by HTTP method |

### Credentials

| Username | Password |
|----------|----------|
| `admin` | `momo2024` |
| `viewer` | `readonly1` |

### Start the API server

```bash
# Make sure modified_sms_v2.xml is in the project root, then:
python api/server.py
```

The terminal will show a startup banner with the server address, transaction count, and quick-copy curl commands. The server runs on **http://localhost:8000**.

### Quick curl tests

```bash
# Health checkconfirm the server is running
curl -u admin:momo2024 http://localhost:8000/health

# List first 5 transactions
curl -u admin:momo2024 "http://localhost:8000/transactions?page=1&per_page=5"

# Filter by transaction type
curl -u admin:momo2024 "http://localhost:8000/transactions?type=BANK_DEPOSIT"

# Get one transaction
curl -u admin:momo2024 http://localhost:8000/transactions/1

# Test 401wrong credentials
curl -u wrong:credentials http://localhost:8000/transactions

# Create a new transaction
curl -u admin:momo2024 -X POST http://localhost:8000/transactions \
  -H "Content-Type: application/json" \
  -d '{"type":"PAYMENT","amount":3000,"fee":0,"receiver":"Kigali SuperMart"}'

# Update a transaction
curl -u admin:momo2024 -X PUT http://localhost:8000/transactions/1 \
  -H "Content-Type: application/json" \
  -d '{"amount":2500,"fee":25}'

# Delete a transaction
curl -u admin:momo2024 -X DELETE http://localhost:8000/transactions/3
```

> Full documentation with request/response examples for every endpoint: [`docs/api_docs.md`](docs/api_docs.md)

### Run the DSA benchmark

```bash
python dsa/dsa_search.py
```

This runs 52 searches on all 1,606 records and prints a comparison between Linear Search O(n) and Dictionary Lookup O(1). Dictionary lookup is **~166x faster**.



## Tech Stack

**Backend**
- Python 3.10+
- `xml.etree.ElementTree`XML parsing (standard library, no install needed)
- `http.server`REST API (standard library, no install needed)
- MySQL 8.0database storage
- FastAPIAPI development (planned for later weeks)

**Frontend**
- HTML5 / CSS3
- Vanilla JavaScript
- Chart.js / D3.js

**Development Tools**
- Git & GitHubversion control
- dbdiagram.ioERD and database design
- GitHub ProjectsAgile workflow management
- VS Code REST ClientAPI testing

## Scrum Board

We are using GitHub Projects to manage our weekly tasks using Agile methodology.

Board: [https://github.com/users/mmugeni/projects/1](https://github.com/users/mmugeni/projects/1)

Columns: `To Do` | `In Progress` | `Done`

## Getting Started

**1. Clone the repo**
```bash
git clone https://github.com/mmugeni/momo-dashboard.git
cd momo-dashboard
```


**3. Set up the database**
```bash
# Open MySQL Workbench, File > Open SQL Script > database/database_setup.sql
```

**4. Run the ETL pipeline**
```bash
bash scripts/run_etl.sh
```

**5. Start the REST API** 
```bash
# Make sure modified_sms_v2.xml is in the project root
python api/server.py
# API available at http://localhost:8000
```

**6. Launch the dashboard**
```bash
bash scripts/serve_frontend.sh
# Open http://localhost:8000
```