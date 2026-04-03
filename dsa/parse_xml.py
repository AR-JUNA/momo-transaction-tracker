"""
parse_xml.py
----------------
I wrote this module to read the MoMo SMS XML file and turn each message
into a clean Python dictionary (JSON-ready object).

The XML has 1,691 SMS records. Not all of them are financial transactions.
Some are OTP messages or system notifications, so I filter those out
and only keep the ones that have real transaction data.

Each SMS body has a different format depending on the transaction type,
so I use regex patterns to extract fields like amount, sender, and balance.

Author: Team Yellow
"""

import xml.etree.ElementTree as ET   # I use this to read the XML file
import re                            # I use this for pattern matching on SMS bodies
import json                          # I use this to save the parsed data to a file
import os                            # I use this to handle file paths


# Transaction type patterns 
# I identified 7 patterns by reading through the XML file manually.
# Each pattern matches a specific kind of MoMo SMS message.

PATTERNS = {
    # "You have received 2000 RWF from Jane Smith..."
    "INCOMING_TRANSFER": re.compile(
        r"You have received (?P<amount>[\d,]+) RWF from (?P<sender>[^(]+?)\s*\(",
        re.IGNORECASE,
    ),

    # "TxId: 73214484437. Your payment of 1,000 RWF to Jane Smith 12845..."
    "PAYMENT": re.compile(
        r"TxId:\s*(?P<tx_id>\d+)\.\s*Your payment of (?P<amount>[\d,]+) RWF to (?P<receiver>[A-Za-z ]+?)\s+\d{3,}",
        re.IGNORECASE,
    ),

    # "*165*S*10000 RWF transferred to Samuel Carter (250791666666)..."
    "PEER_TRANSFER": re.compile(
        r"\*165\*S\*(?P<amount>[\d,]+) RWF transferred to (?P<receiver>[^(]+?)\s*\((?P<receiver_phone>\d+)\)",
        re.IGNORECASE,
    ),

    # "*113*R*A bank deposit of 40000 RWF has been added..."
    "BANK_DEPOSIT": re.compile(
        r"\*113\*R\*A bank deposit of (?P<amount>[\d,]+) RWF has been added",
        re.IGNORECASE,
    ),

    # "withdrawn 20000 RWF from your mobile money account"
    "WITHDRAWAL": re.compile(
        r"withdrawn (?P<amount>[\d,]+) RWF from your mobile money account.*?at (?P<date>[0-9\-: ]+)\.",
        re.IGNORECASE,
    ),

    # "*162*TxId:13913173274*S*Your payment of 2000 RWF to Airtime..."
    "AIRTIME": re.compile(
        r"\*162\*TxId:(?P<tx_id>\d+)\*S\*Your payment of (?P<amount>[\d,]+) RWF to (?P<receiver>[^w][^\*]+)",
        re.IGNORECASE,
    ),

    # "Your payment of 4000 RWF to MTN Cash Power with token..."
    "CASH_POWER": re.compile(
        r"payment of (?P<amount>[\d,]+) RWF to MTN Cash Power with token (?P<token>[\d\-]+)",
        re.IGNORECASE,
    ),
}

# I use this to pull the balance from any SMS body
BALANCE_PATTERN = re.compile(
    r"(?:new balance|NEW BALANCE\s*:?)\s*:?\s*(?P<balance>[\d,]+)\s*RWF",
    re.IGNORECASE,
)

# I use this to pull the fee from any SMS body
FEE_PATTERN = re.compile(
    r"[Ff]ee\s+(?:was|paid)?\s*:?\s*(?P<fee>[\d,]+)\s*RWF",
    re.IGNORECASE,
)

# I use this to pull a date/time stamp from any SMS body
DATE_PATTERN = re.compile(
    r"at\s+(?P<date>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})",
    re.IGNORECASE,
)


def _clean_amount(raw: str) -> float:
    """I remove commas from numbers like '1,000' and return a float."""
    return float(raw.replace(",", ""))


def _extract_common_fields(body: str) -> dict:
    """
    I pull out fields that appear in almost every SMS: balance, fee, and date.
    I return a dict with those values (or None if I can't find them).
    """
    fields = {"balance_after": None, "fee": None, "transaction_date": None}

    balance_match = BALANCE_PATTERN.search(body)
    if balance_match:
        fields["balance_after"] = _clean_amount(balance_match.group("balance"))

    fee_match = FEE_PATTERN.search(body)
    if fee_match:
        fields["fee"] = _clean_amount(fee_match.group("fee"))

    date_match = DATE_PATTERN.search(body)
    if date_match:
        fields["transaction_date"] = date_match.group("date").strip()

    return fields


def _classify_and_parse(sms_id: int, body: str, readable_date: str, raw_date: str) -> dict | None:
    """
    I try each regex pattern against the SMS body.
    If one matches, I build a transaction dictionary and return it.
    If nothing matches, I return None (this SMS is not a transaction).
    """

    # Skip OTP / one-time-password messages — they are not transactions
    if "one-time password" in body.lower() or "otp" in body.lower():
        return None

    common = _extract_common_fields(body)
    base = {
        "id":               sms_id,
        "raw_date":         raw_date,
        "readable_date":    readable_date,
        "transaction_date": common["transaction_date"] or readable_date,
        "balance_after":    common["balance_after"],
        "fee":              common["fee"] or 0.0,
        "raw_body":         body,
    }

    # Try: INCOMING TRANSFER 
    m = PATTERNS["INCOMING_TRANSFER"].search(body)
    if m:
        return {**base,
                "type":   "INCOMING_TRANSFER",
                "amount": _clean_amount(m.group("amount")),
                "sender": m.group("sender").strip(),
                "receiver": None}

    # Try: PEER TRANSFER (*165) 
    m = PATTERNS["PEER_TRANSFER"].search(body)
    if m:
        return {**base,
                "type":           "PEER_TRANSFER",
                "amount":         _clean_amount(m.group("amount")),
                "sender":         None,
                "receiver":       m.group("receiver").strip(),
                "receiver_phone": m.group("receiver_phone")}

    #Try: AIRTIME
    m = PATTERNS["AIRTIME"].search(body)
    if m:
        return {**base,
                "type":     "AIRTIME_PURCHASE",
                "amount":   _clean_amount(m.group("amount")),
                "sender":   None,
                "receiver": "Airtime"}

    #Try: CASH POWER
    m = PATTERNS["CASH_POWER"].search(body)
    if m:
        return {**base,
                "type":     "CASH_POWER",
                "amount":   _clean_amount(m.group("amount")),
                "sender":   None,
                "receiver": "MTN Cash Power"}

    #Try: PAYMENT (merchant / person via TxId) 
    m = PATTERNS["PAYMENT"].search(body)
    if m:
        return {**base,
                "type":     "PAYMENT",
                "tx_id":    m.group("tx_id"),
                "amount":   _clean_amount(m.group("amount")),
                "sender":   None,
                "receiver": m.group("receiver").strip()}

    # Try: BANK DEPOSIT
    m = PATTERNS["BANK_DEPOSIT"].search(body)
    if m:
        return {**base,
                "type":     "BANK_DEPOSIT",
                "amount":   _clean_amount(m.group("amount")),
                "sender":   "Bank",
                "receiver": None}

    # Try: WITHDRAWAL 
    m = PATTERNS["WITHDRAWAL"].search(body)
    if m:
        return {**base,
                "type":     "WITHDRAWAL",
                "amount":   _clean_amount(m.group("amount")),
                "sender":   None,
                "receiver": "Agent"}

    return None   # This SMS is not a financial transaction, so I skip it


def parse_xml(xml_path: str) -> list[dict]:
    """
    I open the XML file, loop through every <sms> element,
    and try to parse each one into a transaction dictionary.

    I return a list of all successfully parsed transactions.
    """
    if not os.path.exists(xml_path):
        raise FileNotFoundError(f"XML file not found at: {xml_path}")

    tree = ET.parse(xml_path)
    root = tree.getroot()

    transactions = []
    sms_id       = 1   # I assign my own IDs starting from 1
    skipped      = 0

    for sms in root.findall("sms"):
        body          = sms.get("body", "").strip()
        readable_date = sms.get("readable_date", "")
        raw_date      = sms.get("date", "")

        result = _classify_and_parse(sms_id, body, readable_date, raw_date)

        if result:
            transactions.append(result)
            sms_id += 1
        else:
            skipped += 1

    print(f"  [Parser] Parsed {len(transactions)} transactions | Skipped {skipped} non-transaction SMS records")
    return transactions


def load_or_parse(xml_path: str, cache_path: str = None) -> list[dict]:
    """
    I check if a cached JSON file exists to avoid re-parsing on every restart.
    If the cache exists I load it, otherwise I parse the XML and save the result.
    """
    if cache_path and os.path.exists(cache_path):
        with open(cache_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        print(f"  [Parser] Loaded {len(data)} transactions from cache ({cache_path})")
        return data

    data = parse_xml(xml_path)

    if cache_path:
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
        print(f"  [Parser] Saved parsed data to cache ({cache_path})")

    return data


#Run this file directly to test the parser
if __name__ == "__main__":
    HERE     = os.path.dirname(os.path.abspath(__file__))
    XML_PATH = os.path.join(HERE, "..", "modified_sms_v2.xml")
    OUT_PATH = os.path.join(HERE, "..", "data", "transactions.json")

    print("\n  Running XML parser...\n")
    txns = load_or_parse(XML_PATH, OUT_PATH)

    print(f"\n  First 3 transactions:\n")
    for t in txns[:3]:
        print(f"    ID {t['id']:>4} | {t['type']:<20} | {t['amount']:>10,.0f} RWF | {t['readable_date']}")

    # Show breakdown by type
    from collections import Counter
    counts = Counter(t["type"] for t in txns)
    print("\n  Breakdown by transaction type:")
    for ttype, count in counts.most_common():
        print(f"    {ttype:<25} {count}")