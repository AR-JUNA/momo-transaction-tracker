# MoMo Transaction Analytics API Reference

>**Base URL:** `http://localhost:8000` &nbsp;·&nbsp; **Format:** JSON &nbsp;·&nbsp; **Auth:** HTTP Basic

Built by **Team Yellow** as part of the Week 4 formative assessment.  
This API sits on top of 1,606 parsed MoMo SMS transactions from `modified_sms_v2.xml` and exposes them through a fully secured REST interface written in plain Python.



## Table of Contents

1. [Overview](#1-overview)
2. [Getting Started](#2-getting-started)
3. [Authentication](#3-authentication)
4. [Data Model](#4-data-model)
5. [Endpoints](#5-endpoints)
   - [GET /transactions](#51-get-transactions)
   - [GET /transactions/{id}](#52-get-transactionsid)
   - [POST /transactions](#53-post-transactions)
   - [PUT /transactions/{id}](#54-put-transactionsid)
   - [DELETE /transactions/{id}](#55-delete-transactionsid)
   - [GET /health](#56-get-health)
   - [GET /stats](#57-get-stats)
6. [Error Reference](#6-error-reference)
7. [Testing the API](#7-testing-the-api)
   - [curl](#71-curl)
   - [VS Code REST Client](#72-vs-code-rest-client)
   - [Python requests](#73-python-requests)
8. [Security Discussion](#8-security-discussion)
9. [Changelog](#9-changelog)



## 1. Overview

We built this API to make the MoMo transaction dataset accessible to any client a frontend dashboard, a mobile app, or a script through a standard HTTP interface. It covers the full CRUD lifecycle: you can list, retrieve, create, update, and delete transaction records.

**What it does:**

- Parses 1,691 raw MoMo SMS records from XML and exposes 1,606 financial transactions as JSON
- Supports pagination and filtering by transaction type on the list endpoint
- Protects every endpoint with HTTP Basic Authentication
- Returns consistent JSON error objects so clients can handle failures predictably
- Logs every request to the terminal with colour-coded status codes

**What it does not do (yet):**

- Write changes back to the MySQL database (the in-memory store resets when the server restarts)
- Support HTTPS (credentials travel in plain text see [Security Discussion](#8-security-discussion))
- Enforce role-based access control (both users currently have the same permissions)


## 2. Getting Started

### Prerequisites

- Python 3.10 or newer
- The `modified_sms_v2.xml` file placed in the project root
- No additional packages required we use only the Python standard library

### Start the server

```bash
# Clone the repo
git clone https://github.com/AR-JUNA/momo-transaction-tracker.git
cd momo-transaction-tracker

# Start the API
python api/server.py
```

On first run, the parser reads the XML and writes a cache to `data/transactions.json`.  
On every run after that, it loads from the cache and starts in under a second.

### Confirm it is running

```bash
curl -u admin:momo2024 http://localhost:8000/health
```

Expected response:

```json
{
  "status": "ok",
  "uptime": "00:00:04",
  "transactions": 1606,
  "total_requests": 1,
  "successful": 1,
  "auth_failures": 0
}
```

---

## 3. Authentication

Every endpoint requires **HTTP Basic Authentication**. We implemented this using the standard `Authorization` header as defined in [RFC 7617](https://datatracker.ietf.org/doc/html/rfc7617).

### How it works

When you make a request, you include an `Authorization` header whose value is the word `Basic` followed by a space and then `username:password` encoded in base64.

```
Authorization: Basic YWRtaW46bW9tbzIwMjQ=
```

> `YWRtaW46bW9tbzIwMjQ=` is base64 for `admin:momo2024`

You do not need to encode this manually. Both curl and the VS Code REST Client handle it automatically when you pass the credentials directly.

### Credentials

| Username | Password    | Level        | Notes                              |
|----------|-------------|--------------|-------------------------------------|
| `admin`  | `momo2024`  | Full access  | Can read, create, update, and delete |
| `viewer` | `readonly1` | Read only    | Intended for GET requests only       |

### Successful authentication

A correctly authenticated request returns the expected response with a `200` or `201` status and these response headers:

```
Content-Type: application/json; charset=utf-8
Access-Control-Allow-Origin: *
X-Powered-By: MoMo Analytics API / Team Yellow
```

### Failed authentication

If the `Authorization` header is missing or the credentials are wrong, every endpoint returns the same `401` response:

```json
{
  "error": "Unauthorized. Provide valid Basic Auth credentials.",
  "status": 401
}
```

The server also sends back:

```
WWW-Authenticate: Basic realm="MoMo API"
```

This tells the client it needs Basic credentials browsers will show a login popup when they see this header.



## 4. Data Model

Every transaction object returned by the API has the following fields:

| Field              | Type        | Always present | Description                                                 |
|--------------------|-------------|:--------------:|-------------------------------------------------------------|
| `id`               | integer     | ✓              | Sequential ID we assign at parse time                       |
| `type`             | string      | ✓              | Transaction category see type table below                 |
| `amount`           | float       | ✓              | Amount in RWF (Rwandan Franc)                               |
| `fee`              | float       | ✓              | Fee charged in RWF. `0.0` when the SMS says "Fee was 0"     |
| `balance_after`    | float       | ✓              | Wallet balance after this transaction                       |
| `sender`           | string/null |              | Sender name if the SMS mentions one, otherwise `null`       |
| `receiver`         | string/null |              | Receiver name, merchant, or service label                   |
| `receiver_phone`   | string/null |              | Receiver phone only present on `PEER_TRANSFER` records    |
| `tx_id`            | string/null |              | MTN reference number from the SMS body                      |
| `transaction_date` | string      | ✓              | Date and time extracted from inside the SMS body            |
| `readable_date`    | string      | ✓              | Human-readable date from the XML `readable_date` attribute  |
| `raw_body`         | string      | ✓              | Original SMS text we parsed this record from                |
| `created_at`       | string/null |              | ISO 8601 only present on records added via POST           |
| `updated_at`       | string/null |              | ISO 8601 only present after a PUT update                  |

### Transaction types

| Type                | Source pattern in SMS                             | Count |
|---------------------|---------------------------------------------------|------:|
| `PAYMENT`           | `TxId: XXXXXXXXX. Your payment of X RWF to...`   | 658   |
| `PEER_TRANSFER`     | `*165*S* X RWF transferred to Name (phone)`       | 585   |
| `BANK_DEPOSIT`      | `*113*R* A bank deposit of X RWF has been added`  | 248   |
| `INCOMING_TRANSFER` | `You have received X RWF from Name`               | 63    |
| `AIRTIME_PURCHASE`  | `*162*TxId:... Your payment of X RWF to Airtime`  | 52    |
| **Total**           |                                                   | **1,606** |

---

## 5. Endpoints

### 5.1 GET /transactions

Returns a paginated list of all transactions. Optionally filtered by type.

#### Query parameters

| Parameter  | Type    | Default | Constraints  | Description                            |
|------------|---------|---------|:------------:|----------------------------------------|
| `page`     | integer | `1`     | ≥ 1          | Which page of results to return        |
| `per_page` | integer | `50`    | 1 – 200      | How many records to include per page   |
| `type`     | string  |       | See type list | Filter to one transaction type        |

#### Response envelope

| Field         | Type    | Description                                |
|---------------|---------|--------------------------------------------|
| `status`      | string  | Always `"success"` on a `200` response     |
| `page`        | integer | Current page number                        |
| `per_page`    | integer | Records per page used for this response    |
| `total`       | integer | Total matching records across all pages    |
| `total_pages` | integer | How many pages exist at this `per_page`    |
| `data`        | array   | Array of transaction objects               |

#### curl

```bash
# Default first 50 transactions
curl -u admin:momo2024 http://localhost:8000/transactions

# With pagination
curl -u admin:momo2024 "http://localhost:8000/transactions?page=2&per_page=10"

# Filter to one type
curl -u admin:momo2024 "http://localhost:8000/transactions?type=BANK_DEPOSIT"

# Combine filter and pagination
curl -u admin:momo2024 "http://localhost:8000/transactions?type=PEER_TRANSFER&page=1&per_page=5"
```

#### Response 200 OK

```json
{
  "status": "success",
  "page": 1,
  "per_page": 5,
  "total": 1606,
  "total_pages": 322,
  "data": [
    {
      "id": 1,
      "type": "INCOMING_TRANSFER",
      "amount": 2000.0,
      "fee": 0.0,
      "balance_after": 2000.0,
      "sender": "Jane Smith",
      "receiver": null,
      "transaction_date": "2024-05-10 16:30:51",
      "readable_date": "10 May 2024 4:30:58 PM",
      "raw_body": "You have received 2000 RWF from Jane Smith (*********013)..."
    },
    {
      "id": 2,
      "type": "PAYMENT",
      "amount": 1000.0,
      "fee": 0.0,
      "balance_after": 1000.0,
      "sender": null,
      "receiver": "Jane Smith",
      "tx_id": "73214484437",
      "transaction_date": "2024-05-10 16:31:39",
      "readable_date": "10 May 2024 4:31:46 PM",
      "raw_body": "TxId: 73214484437. Your payment of 1,000 RWF to Jane Smith..."
    }
  ]
}
```

---

### 5.2 GET /transactions/{id}

Returns a single transaction by its integer ID. We use a dictionary lookup internally, so this is O(1) regardless of dataset size.

#### Path parameter

| Parameter | Type    | Description                   |
|-----------|---------|-------------------------------|
| `id`      | integer | The transaction's assigned ID |

#### curl

```bash
curl -u admin:momo2024 http://localhost:8000/transactions/1
```

#### Response 200 OK

```json
{
  "status": "success",
  "data": {
    "id": 1,
    "type": "INCOMING_TRANSFER",
    "amount": 2000.0,
    "fee": 0.0,
    "balance_after": 2000.0,
    "sender": "Jane Smith",
    "receiver": null,
    "transaction_date": "2024-05-10 16:30:51",
    "readable_date": "10 May 2024 4:30:58 PM",
    "raw_body": "You have received 2000 RWF from Jane Smith (*********013) on your mobile money account at 2024-05-10 16:30:51. Your new balance:2000 RWF. Financial Transaction Id: 76662021700."
  }
}
```

#### Response 404 Not Found

```json
{
  "error": "Transaction with id=9999 not found.",
  "status": 404
}
```


### 5.3 POST /transactions

Adds a new transaction record to the in-memory store. The server assigns the next available ID automatically and stamps a `created_at` timestamp.

#### Required body fields

| Field    | Type   | Description                               |
|----------|--------|-------------------------------------------|
| `type`   | string | Must be a valid transaction type          |
| `amount` | float  | Must be a positive number greater than `0` |

#### Optional body fields

| Field              | Type   | Description                              |
|--------------------|--------|------------------------------------------|
| `fee`              | float  | Fee in RWF. Defaults to `0.0`            |
| `sender`           | string | Name of the sender                       |
| `receiver`         | string | Name of the receiver                     |
| `balance_after`    | float  | Wallet balance after this transaction    |
| `transaction_date` | string | Date/time string for this transaction    |

#### curl

```bash
curl -u admin:momo2024 \
  -X POST http://localhost:8000/transactions \
  -H "Content-Type: application/json" \
  -d '{
    "type": "PEER_TRANSFER",
    "amount": 5000,
    "fee": 50,
    "sender": "Amina Uwimana",
    "receiver": "Olivier Nkurunziza",
    "balance_after": 47000
  }'
```

#### Response 201 Created

```json
{
  "status": "created",
  "data": {
    "type": "PEER_TRANSFER",
    "amount": 5000,
    "fee": 50,
    "sender": "Amina Uwimana",
    "receiver": "Olivier Nkurunziza",
    "balance_after": 47000,
    "id": 1607,
    "created_at": "2024-06-01T10:00:00.000000+00:00Z"
  }
}
```

#### Response 400 Bad Request (missing required field)

```json
{
  "error": "Missing required fields: ['amount']",
  "status": 400
}
```

#### Response 400 Bad Request (invalid amount)

```json
{
  "error": "Field 'amount' must be a positive number.",
  "status": 400
}
```

---

### 5.4 PUT /transactions/{id}

Partially updates an existing transaction. You only send the fields you want to change all other fields stay as they were. The server adds an `updated_at` timestamp to the record.

> **Note:** You cannot change a record's `id`. If you include `id` in the body, we ignore it silently.

#### Path parameter

| Parameter | Type    | Description                            |
|-----------|---------|----------------------------------------|
| `id`      | integer | The ID of the transaction to update    |

#### curl

```bash
# Update amount and fee only
curl -u admin:momo2024 \
  -X PUT http://localhost:8000/transactions/1 \
  -H "Content-Type: application/json" \
  -d '{"amount": 2500, "fee": 25}'

# Update just the type
curl -u admin:momo2024 \
  -X PUT http://localhost:8000/transactions/5 \
  -H "Content-Type: application/json" \
  -d '{"type": "PAYMENT"}'
```

#### Response 200 OK

```json
{
  "status": "updated",
  "data": {
    "id": 1,
    "type": "INCOMING_TRANSFER",
    "amount": 2500,
    "fee": 25,
    "balance_after": 2000.0,
    "sender": "Jane Smith",
    "receiver": null,
    "transaction_date": "2024-05-10 16:30:51",
    "readable_date": "10 May 2024 4:30:58 PM",
    "updated_at": "2024-06-01T10:05:00.000000+00:00Z"
  }
}
```

#### Response 404 Not Found

```json
{
  "error": "Transaction with id=9999 not found.",
  "status": 404
}
```

#### Response 400 Bad Request (empty body)

```json
{
  "error": "Request body cannot be empty.",
  "status": 400
}
```

---

### 5.5 DELETE /transactions/{id}

Permanently removes a transaction from the in-memory store. This cannot be undone in the current session restart the server to reload from the XML cache.

#### Path parameter

| Parameter | Type    | Description                            |
|-----------|---------|----------------------------------------|
| `id`      | integer | The ID of the transaction to delete    |

#### curl

```bash
curl -u admin:momo2024 -X DELETE http://localhost:8000/transactions/3
```

#### Response 200 OK

```json
{
  "status": "deleted",
  "id": 3
}
```

#### Confirming the deletion

```bash
# Requesting a deleted ID should return 404
curl -u admin:momo2024 http://localhost:8000/transactions/3
```

```json
{
  "error": "Transaction with id=3 not found.",
  "status": 404
}
```

---

### 5.6 GET /health

Returns the server's current status and aggregate request counts. We use this to confirm the server is alive before running a test sequence.

#### curl

```bash
curl -u admin:momo2024 http://localhost:8000/health
```

#### Response 200 OK

```json
{
  "status": "ok",
  "uptime": "00:12:45",
  "transactions": 1606,
  "total_requests": 24,
  "successful": 22,
  "auth_failures": 2
}
```

| Field            | Type    | Description                                       |
|------------------|---------|---------------------------------------------------|
| `status`         | string  | `"ok"` when the server is healthy                 |
| `uptime`         | string  | Time since server start in `HH:MM:SS` format      |
| `transactions`   | integer | Number of transactions in the store right now     |
| `total_requests` | integer | All requests received since startup               |
| `successful`     | integer | Requests that returned 2xx                        |
| `auth_failures`  | integer | Requests that returned 401                        |

---

### 5.7 GET /stats

Returns request counts broken down by HTTP method. Useful during testing to confirm all methods are being exercised.

#### curl

```bash
curl -u admin:momo2024 http://localhost:8000/stats
```

#### Response 200 OK

```json
{
  "uptime": "00:12:45",
  "total_requests": 24,
  "by_method": {
    "GET": 18,
    "POST": 3,
    "PUT": 2,
    "DELETE": 1
  },
  "auth_failures": 2,
  "not_found": 1,
  "server_errors": 0,
  "transactions_in_memory": 1606
}
```

---

## 6. Error Reference

Every error response follows the same structure so any client can parse it consistently:

```json
{
  "error": "Human-readable description of what went wrong.",
  "status": 404
}
```

### Status codes

| Code  | Status Text       | When we return it                                                                      |
|-------|-------------------|----------------------------------------------------------------------------------------|
| `200` | OK                | Request succeeded. Body contains the requested data.                                   |
| `201` | Created           | POST succeeded. Body contains the newly created record including its assigned ID.      |
| `400` | Bad Request       | Body has invalid JSON, is missing required fields, or contains an invalid value.       |
| `401` | Unauthorized      | `Authorization` header is missing, malformed, or the credentials do not match.        |
| `404` | Not Found         | The transaction ID does not exist, or the URL is not a valid route.                   |
| `405` | Method Not Allowed| The HTTP method is not supported on that path.                                        |

### Common mistakes

| Symptom                              | Likely cause                                     | Fix                                                           |
|--------------------------------------|--------------------------------------------------|---------------------------------------------------------------|
| `401` on every request               | Credentials wrong or missing                     | Use `-u admin:momo2024` in curl                               |
| `400` with "Invalid JSON"            | Single quotes in the body on Windows cmd         | Use a `.http` file or escape the JSON properly                |
| `404` on a valid ID                  | Record was deleted in this session               | Restart the server to reload from the XML cache               |
| `400` "Missing required fields"      | POST body is missing `type` or `amount`          | Double-check your JSON body                                   |
| Empty `data` array on a type filter  | `type` value does not match exactly              | Types are uppercase use `PAYMENT` not `payment`             |



## 7. Testing the API

### 7.1 curl

curl ships with macOS, Linux, and Windows 10+. It is the primary tool we use for testing this API.

**Useful flags:**

| Flag           | What it does                                      |
|----------------|---------------------------------------------------|
| `-u user:pass` | Sends Basic Auth header automatically             |
| `-X METHOD`    | Sets the HTTP method (POST, PUT, DELETE)          |
| `-H "header"`  | Adds a request header                             |
| `-d '...'`     | Sends a request body (string)                     |
| `-i`           | Shows response headers as well as the body        |
| `-s`           | Silent mode hides the progress bar              |

**Full test sequence run these in order:**

```bash
BASE="http://localhost:8000"
AUTH="admin:momo2024"

# 1. Server health
curl -s -u $AUTH $BASE/health | python3 -m json.tool

# 2. List first 5 transactions
curl -s -u $AUTH "$BASE/transactions?page=1&per_page=5" | python3 -m json.tool

# 3. Filter by type
curl -s -u $AUTH "$BASE/transactions?type=BANK_DEPOSIT&per_page=3" | python3 -m json.tool

# 4. Get one transaction
curl -s -u $AUTH $BASE/transactions/1 | python3 -m json.tool

# 5. Test 401 wrong credentials
curl -s -u wrong:password $BASE/transactions | python3 -m json.tool

# 6. Test 404 ID that does not exist
curl -s -u $AUTH $BASE/transactions/99999 | python3 -m json.tool

# 7. Create a new transaction (POST)
curl -s -u $AUTH -X POST $BASE/transactions \
  -H "Content-Type: application/json" \
  -d '{"type":"PAYMENT","amount":3000,"fee":0,"receiver":"Kigali SuperMart"}' \
  | python3 -m json.tool

# 8. Update that transaction (PUT)
curl -s -u $AUTH -X PUT $BASE/transactions/1 \
  -H "Content-Type: application/json" \
  -d '{"amount":2500,"fee":25}' \
  | python3 -m json.tool

# 9. Delete a transaction
curl -s -u $AUTH -X DELETE $BASE/transactions/3 | python3 -m json.tool

# 10. Confirm it is gone (expect 404)
curl -s -u $AUTH $BASE/transactions/3 | python3 -m json.tool

# 11. Check stats after all the above
curl -s -u $AUTH $BASE/stats | python3 -m json.tool
```

> Piping to `python3 -m json.tool` formats the JSON neatly in the terminal. No extra dependencies needed.

---

### 7.2 VS Code REST Client

If you are working in VS Code, the **REST Client** extension lets you write and run HTTP requests directly from a `.http` file in your editor no separate tool needed.

**Install:**

1. Open VS Code
2. Go to Extensions (`Ctrl+Shift+X`)
3. Search for `REST Client` (by Huachao Mao)
4. Click Install


### 7.3 Python requests

For anyone writing a script that calls our API:

```python
import requests
from requests.auth import HTTPBasicAuth

BASE = "http://localhost:8000"
AUTH = HTTPBasicAuth("admin", "momo2024")

# GET all first page
r = requests.get(f"{BASE}/transactions", auth=AUTH, params={"page": 1, "per_page": 5})
print(r.status_code)           # 200
print(r.json()["total"])       # 1606

# GET one by ID
r = requests.get(f"{BASE}/transactions/1", auth=AUTH)
txn = r.json()["data"]
print(txn["type"], txn["amount"])    # INCOMING_TRANSFER 2000.0

# POST create new
payload = {
    "type":     "PAYMENT",
    "amount":   3000,
    "fee":      0,
    "receiver": "Kigali SuperMart"
}
r = requests.post(f"{BASE}/transactions", auth=AUTH, json=payload)
print(r.status_code)                 # 201
print(r.json()["data"]["id"])        # new ID assigned by the server

# PUT partial update
r = requests.put(
    f"{BASE}/transactions/1",
    auth=AUTH,
    json={"amount": 2500, "fee": 25}
)
print(r.json()["status"])    # updated

# DELETE
r = requests.delete(f"{BASE}/transactions/3", auth=AUTH)
print(r.json()["status"])    # deleted
```


## 8. Security Discussion

### How Basic Auth works in our implementation

When a request arrives, the server reads the `Authorization` header. We take the value after `Basic `, base64-decode it, and split on the first colon to get `username` and `password`. We then check that pair against a dictionary of valid users. If it matches, the request continues. If not, we return 401 immediately.

### Why it is not sufficient for production

**Credentials travel on every single request.**  
Base64 is encoding, not encryption. Without HTTPS, the string `YWRtaW46bW9tbzIwMjQ=` is visible to anyone reading network traffic, and it decodes back to `admin:momo2024` in one second.

**No expiry.**  
Once someone has the password, it works forever. There is no way to invalidate a session without changing the password for all users.

**No permission scoping.**  
We cannot issue a credential that only permits reading `PAYMENT` records, or that expires after one hour, or that is tied to a specific IP address.

### What we would use in production

| Method              | How it works                                                                                     | Key advantage                                              |
|---------------------|--------------------------------------------------------------------------------------------------|------------------------------------------------------------|
| **JWT**             | Client logs in once. Server returns a signed token. Only the token travels on future requests.   | Token expires automatically. Password never travels again. |
| **OAuth 2.0**       | A dedicated auth server issues access tokens with defined scopes and refresh tokens.             | Industry standard. Supports third-party login and fine-grained permissions. |
| **API Keys + HTTPS**| A long random key per client sent in `X-API-Key` over TLS.                                      | Simple to implement, easy to revoke, good for server-to-server calls. |

For a MoMo dashboard used from a mobile app, we would implement JWT with refresh tokens over HTTPS, with the signing secret stored in an environment variable never in source code.

---

## 9. Changelog

| Version | Date       | Changes                                                              |
|---------|------------|----------------------------------------------------------------------|
| v1.0    | 2026-03-31 | Initial release                                                      |
|         |            | All 5 CRUD endpoints + `/health` + `/stats`                          |
|         |            | Basic Auth on all endpoints with WWW-Authenticate challenge header   |
|         |            | Pagination and `type` filter on `GET /transactions`                  |
|         |            | In-memory store with O(1) dictionary lookup and thread-safe locking  |
|         |            | Colour-coded terminal request log with startup banner                |

---

*MoMo Transaction Analytics API Team Yellow Week 4 Formative Assessment*  
*Repository: [https://github.com/AR-JUNA/momo-transaction-tracker.git](https://github.com/AR-JUNA/momo-transaction-tracker.git)*