"""
parse_xml.py
------------
Parses modified_sms_v2.xml and converts each SMS record into a
structured JSON object (Python dictionary).

"""

import xml.etree.ElementTree as ET
import re
import json
import os
from datetime import datetime

# Category detection patterns 

PATTERNS = {
    "INCOMING_TRANSFER": re.compile(
        r"You have received (?P<amount>[\d,]+) RWF from (?P<sender>[^(]+)\s*\(",
        re.IGNORECASE,
    ),
    "OUTGOING_TRANSFER": re.compile(
        r"\*165\*S\*(?P<amount>[\d,]+) RWF transferred to (?P<receiver>[^\(]+)\s*\((?P<receiver_phone>[^)]+)\)",
        re.IGNORECASE,
    ),
    "PAYMENT": re.compile(
        r"TxId:\s*(?P<txid>\d+).*?payment of (?P<amount>[\d,]+) RWF to (?P<receiver>[^\d]+?)\s+\d+",
        re.IGNORECASE,
    ),
    "DEPOSIT": re.compile(
        r"bank deposit of (?P<amount>[\d,]+) RWF has been added",
        re.IGNORECASE,
    ),
    "WITHDRAWAL": re.compile(
        r"withdrawn (?P<amount>[\d,]+) RWF from your mobile money",
        re.IGNORECASE,
    ),
    "AIRTIME": re.compile(
        r"payment of (?P<amount>[\d,]+) RWF to Airtime",
        re.IGNORECASE,
    ),
    "UTILITY": re.compile(
        r"payment of (?P<amount>[\d,]+) RWF to MTN Cash Power",
        re.IGNORECASE,
    ),
    "THIRD_PARTY": re.compile(
        r"transaction of (?P<amount>[\d,]+) RWF by (?P<party>[^\s].*?) on your MOMO",
        re.IGNORECASE,
    ),
    "OTP": re.compile(r"one-time password", re.IGNORECASE),
}

BALANCE_RE    = re.compile(r"[Nn]ew balance[:\s]+(?P<bal>[\d,]+)\s*RWF", re.IGNORECASE)
FEE_RE        = re.compile(r"[Ff]ee (?:was|paid)[:\s]+(?P<fee>[\d,]+)\s*RWF", re.IGNORECASE)
TXID_RE       = re.compile(r"TxId[:\s*]+(?P<txid>\d+)", re.IGNORECASE)
FIN_TXID_RE   = re.compile(r"Financial Transaction Id[:\s]+(?P<txid>\d+)", re.IGNORECASE)
DATE_RE       = re.compile(r"at\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})")


def _clean_amount(raw: str) -> float:
    """Remove commas and convert to float."""
    try:
        return float(str(raw).replace(",", "").strip())
    except (ValueError, TypeError):
        return 0.0


def _extract_fields(body: str) -> dict:
    """Extract common fields from any SMS body."""
    fields = {
        "amount":       0.0,
        "fee":          0.0,
        "new_balance":  None,
        "transaction_id": None,
        "transaction_date": None,
        "sender":       None,
        "receiver":     None,
        "receiver_phone": None,
        "category":     "UNKNOWN",
    }

    # Transaction date
    date_match = DATE_RE.search(body)
    if date_match:
        fields["transaction_date"] = date_match.group(1)

    # Balance
    bal_match = BALANCE_RE.search(body)
    if bal_match:
        fields["new_balance"] = _clean_amount(bal_match.group("bal"))

    # Fee
    fee_match = FEE_RE.search(body)
    if fee_match:
        fields["fee"] = _clean_amount(fee_match.group("fee"))

    # Transaction ID — try TxId first then Financial Transaction Id
    txid_match = TXID_RE.search(body)
    if txid_match:
        fields["transaction_id"] = txid_match.group("txid")
    else:
        fin_match = FIN_TXID_RE.search(body)
        if fin_match:
            fields["transaction_id"] = fin_match.group("txid")

    return fields


def _categorise(body: str, fields: dict) -> dict:
    """Run pattern matching and fill category-specific fields."""

    if PATTERNS["OTP"].search(body):
        fields["category"] = "OTP"
        return fields

    if PATTERNS["AIRTIME"].search(body):
        fields["category"] = "AIRTIME"
        m = PATTERNS["AIRTIME"].search(body)
        fields["amount"] = _clean_amount(m.group("amount"))
        return fields

    if PATTERNS["UTILITY"].search(body):
        fields["category"] = "UTILITY_PAYMENT"
        m = PATTERNS["UTILITY"].search(body)
        fields["amount"] = _clean_amount(m.group("amount"))
        return fields

    if PATTERNS["DEPOSIT"].search(body):
        fields["category"] = "DEPOSIT"
        m = PATTERNS["DEPOSIT"].search(body)
        fields["amount"] = _clean_amount(m.group("amount"))
        return fields

    if PATTERNS["WITHDRAWAL"].search(body):
        fields["category"] = "WITHDRAWAL"
        m = PATTERNS["WITHDRAWAL"].search(body)
        fields["amount"] = _clean_amount(m.group("amount"))
        return fields

    if PATTERNS["INCOMING_TRANSFER"].search(body):
        fields["category"] = "INCOMING_TRANSFER"
        m = PATTERNS["INCOMING_TRANSFER"].search(body)
        fields["amount"]  = _clean_amount(m.group("amount"))
        fields["sender"]  = m.group("sender").strip()
        return fields

    if PATTERNS["OUTGOING_TRANSFER"].search(body):
        fields["category"] = "OUTGOING_TRANSFER"
        m = PATTERNS["OUTGOING_TRANSFER"].search(body)
        fields["amount"]         = _clean_amount(m.group("amount"))
        fields["receiver"]       = m.group("receiver").strip()
        fields["receiver_phone"] = m.group("receiver_phone").strip()
        return fields

    if PATTERNS["PAYMENT"].search(body):
        fields["category"] = "PAYMENT"
        m = PATTERNS["PAYMENT"].search(body)
        fields["amount"]   = _clean_amount(m.group("amount"))
        fields["receiver"] = m.group("receiver").strip()
        return fields

    if PATTERNS["THIRD_PARTY"].search(body):
        fields["category"] = "THIRD_PARTY_DEBIT"
        m = PATTERNS["THIRD_PARTY"].search(body)
        fields["amount"]   = _clean_amount(m.group("amount"))
        fields["sender"]   = m.group("party").strip()
        return fields

    return fields


def parse_xml(filepath: str) -> list[dict]:
    """
    Parse the XML file and return a list of transaction dictionaries.
    Each dictionary represents one SMS record with all extracted fields.
    """
    tree = ET.parse(filepath)
    root = tree.getroot()

    transactions = []
    sms_id = 1

    for sms in root.findall("sms"):
        body          = sms.get("body", "")
        readable_date = sms.get("readable_date", "")
        raw_date_ms   = sms.get("date", "0")

        fields = _extract_fields(body)
        fields = _categorise(body, fields)

        # Fallback: use readable_date if no in-body date found
        if not fields["transaction_date"]:
            fields["transaction_date"] = readable_date

        record = {
            "id":               sms_id,
            "transaction_id":   fields["transaction_id"],
            "category":         fields["category"],
            "amount":           fields["amount"],
            "fee":              fields["fee"],
            "new_balance":      fields["new_balance"],
            "sender":           fields["sender"],
            "receiver":         fields["receiver"],
            "receiver_phone":   fields["receiver_phone"],
            "transaction_date": fields["transaction_date"],
            "raw_date_ms":      int(raw_date_ms),
            "raw_body":         body,
        }

        transactions.append(record)
        sms_id += 1

    return transactions


# Quick check 
if __name__ == "__main__":
    BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    xml_path = os.path.join(BASE, "modified_sms_v2.xml")
    txns = parse_xml(xml_path)
    print(f"Parsed {len(txns)} SMS records")
    categories = {}
    for t in txns:
        categories[t["category"]] = categories.get(t["category"], 0) + 1
    print("Category breakdown:")
    for cat, count in sorted(categories.items()):
        print(f"  {cat:<25} {count}")
    # Preview first record
    print("\nFirst record:")
    print(json.dumps(txns[0], indent=2))