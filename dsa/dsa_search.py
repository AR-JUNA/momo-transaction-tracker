"""
dsa_search.py
-----------------
I compare two methods for searching transactions by ID:

  1. Linear Search  - I loop through the entire list from the start until I
                      find the record. Time complexity: O(n).

  2. Dictionary Lookup - I store all transactions in a dictionary where the
                         key is the transaction ID. Finding any record is
                         instant. Time complexity: O(1).

I run four benchmark sizes: 20, 100, 500, and all records.
Then I print a full summary table with averages at the bottom.


"""

import time       # I use this to measure how long each search takes
import random     # I use this to pick random IDs for the benchmark
import sys
import os

# I need the api directory on the path so I can import the parser
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "api"))
from parse_xml import parse_xml


# 1.  Linear Search

def linear_search(transactions: list[dict], target_id: int) -> dict | None:
    """
    I scan through every transaction in the list one by one.
    As soon as I find the one with the matching ID, I return it.
    If I reach the end without finding it, I return None.

    Time complexity: O(n) - in the worst case I check every record.
    Space complexity: O(1) - I don't create any extra data structures.
    """
    for transaction in transactions:
        if transaction["id"] == target_id:
            return transaction
    return None   # not found


# 2.  Dictionary Lookup (Hash Map)

def build_lookup_dict(transactions: list[dict]) -> dict[int, dict]:
    """
    I take the list of transactions and build a dictionary where:
      - the key   is the transaction ID (an integer)
      - the value is the full transaction dictionary

    I only need to build this once. After that, every lookup is O(1).

    Time complexity to build: O(n)
    Space complexity: O(n) - I keep a second copy of the data in memory
    """
    return {txn["id"]: txn for txn in transactions}


def dict_lookup(lookup: dict[int, dict], target_id: int) -> dict | None:
    """
    I find a transaction by its ID using a dictionary key lookup.
    Python dictionaries use a hash table internally, so this is O(1) -
    it does NOT matter how many records there are.

    Time complexity: O(1)
    Space complexity: O(1) - no extra memory used per lookup
    """
    return lookup.get(target_id, None)


# 3.  Benchmark - I measure and compare both methods

def run_benchmark(transactions: list[dict], num_searches: int) -> dict:
    """
    I run the same set of ID lookups using both methods and record
    how long each one takes.

    I search for `num_searches` random IDs so the results are fair.
    I include both IDs that exist in the list and some that don't,
    to test the worst-case scenario (full scan for linear search).

    Returns a dict with timing results and summary stats.
    """
    if not transactions:
        raise ValueError("Transaction list is empty - cannot benchmark.")

    # I build the dictionary once before the benchmark starts
    lookup_dict = build_lookup_dict(transactions)

    # I pick random IDs from the dataset to search for
    all_ids    = [t["id"] for t in transactions]
    sample_ids = random.choices(all_ids, k=num_searches)
    # I add two IDs that don't exist to force worst-case on linear search
    max_id      = max(all_ids)
    sample_ids += [max_id + 100, max_id + 200]
    total       = len(sample_ids)

    # Time the linear search 
    linear_start = time.perf_counter()
    linear_hits  = 0
    for sid in sample_ids:
        result = linear_search(transactions, sid)
        if result:
            linear_hits += 1
    linear_time = time.perf_counter() - linear_start

    #  Time the dictionary lookup 
    dict_start = time.perf_counter()
    dict_hits  = 0
    for sid in sample_ids:
        result = dict_lookup(lookup_dict, sid)
        if result:
            dict_hits += 1
    dict_time = time.perf_counter() - dict_start

    speedup = linear_time / dict_time if dict_time > 0 else float("inf")

    return {
        "dataset_size":  len(transactions),
        "num_searches":  total,
        "linear_search": {
            "total_time_ms": round(linear_time * 1000, 4),
            "avg_time_us":   round((linear_time / total) * 1_000_000, 4),
            "hits":          linear_hits,
        },
        "dict_lookup": {
            "total_time_ms": round(dict_time * 1000, 4),
            "avg_time_us":   round((dict_time / total) * 1_000_000, 4),
            "hits":          dict_hits,
        },
        "speedup_factor": round(speedup, 1),
    }


# 4.  Terminal output helpers

W   = 85
SEP = "─" * W
DBL = "═" * W
THN = "·" * W


def _bar(value: float, max_val: float, width: int = 20) -> str:
    """I draw a small ASCII progress bar proportional to the value."""
    if max_val == 0:
        return "─" * width
    filled = round((value / max_val) * width)
    filled = max(1, filled)
    return "█" * filled + "░" * (width - filled)


def print_single_result(r: dict, label: str) -> None:
    """I print one benchmark result as a clean labelled block."""
    ls      = r["linear_search"]
    dl      = r["dict_lookup"]
    max_ms  = ls["total_time_ms"]   # linear is always the slower one

    print(f"\n  ┌─ {label}")
    print(f"  │  Dataset : {r['dataset_size']:,} records     "
          f"Searches run : {r['num_searches']}")
    print(f"  │")
    print(f"  │  {'Method':<26} {'Total (ms)':>11}  "
          f"{'Avg/search (µs)':>15}  {'Hits':>5}")
    print(f"  │  {'─'*26}  {'─'*11}  {'─'*15}  {'─'*5}")
    print(f"  │  {'Linear Search    O(n)':<26}  "
          f"{ls['total_time_ms']:>11.4f}  "
          f"{ls['avg_time_us']:>15.4f}  "
          f"{ls['hits']:>5}  "
          )
    print(f"  │  {'Dictionary Lookup O(1)':<26}  "
          f"{dl['total_time_ms']:>11.4f}  "
          f"{dl['avg_time_us']:>15.4f}  "
          f"{dl['hits']:>5}  "
    )
    print(f"  │")
    print(f"  └─ Dictionary is {r['speedup_factor']}x faster than linear search")


def print_summary_table(all_results: list[dict], labels: list[str]) -> None:
    """
    I print the full comparison summary — one row per benchmark run,
    plus an averages row at the bottom.
    """
    print(f"\n\n  {DBL}")
    print(f"  {'SUMMARY — ALL BENCHMARK RUNS':^{W}}")
    print(f"  {DBL}")
    print(
        f"  {'Benchmark':<32} "
        f"{'Records':>8} "
        f"{'Searches':>9} "
        f"{'Linear (ms)':>12} "
        f"{'Dict (ms)':>10} "
        f"{'Speedup':>8}"
    )
    print(f"  {SEP}")

    for label, r in zip(labels, all_results):
        print(
            f"  {label:<32} "
            f"{r['dataset_size']:>8,} "
            f"{r['num_searches']:>9,} "
            f"{r['linear_search']['total_time_ms']:>12.4f} "
            f"{r['dict_lookup']['total_time_ms']:>10.4f} "
            f"{r['speedup_factor']:>7.1f}x"
        )

    print(f"  {SEP}")

    # Averages row 
    avg_linear   = sum(r["linear_search"]["total_time_ms"] for r in all_results) / len(all_results)
    avg_dict     = sum(r["dict_lookup"]["total_time_ms"]   for r in all_results) / len(all_results)
    avg_speedup  = sum(r["speedup_factor"]                 for r in all_results) / len(all_results)
    avg_lin_us   = sum(r["linear_search"]["avg_time_us"]   for r in all_results) / len(all_results)
    avg_dict_us  = sum(r["dict_lookup"]["avg_time_us"]     for r in all_results) / len(all_results)

    print(
        f"  {'AVERAGE (all runs)':<32} "
        f"{'':>8} "
        f"{'':>9} "
        f"{avg_linear:>12.4f} "
        f"{avg_dict:>10.4f} "
        f"{avg_speedup:>7.1f}x"
    )
    print(f"  {DBL}")

    #  Per-search averages 
    print(f"\n  Average time per single search (averaged across all runs):")
    print(f"  {THN}")
    print(f"  Linear Search    O(n)   avg  {avg_lin_us:>9.4f} µs  per lookup")
    print(f"  Dictionary       O(1)   avg  {avg_dict_us:>9.4f} µs  per lookup")
    print(f"  {THN}")
    print(f"  Overall: dictionary lookup is {avg_speedup:.1f}x faster on average")
    print(f"  {DBL}")


# 5.  Entry point

if __name__ == "__main__":

    HERE     = os.path.dirname(os.path.abspath(__file__))
    XML_PATH = os.path.join(HERE, "..", "modified_sms_v2.xml")

    #Header
    print(f"\n  {DBL}")
    print(f"  {'MoMo DSA Benchmark  —  Team Yellow  —  Week 4':^{W}}")
    print(f"  {DBL}")

    # Load data
    print(f"\n  Loading transactions from XML ...")
    transactions = parse_xml(XML_PATH)
    print(f"  Done. {len(transactions):,} transaction records loaded.\n")
    print(f"  {THN}")
    print(f"  Running 4 benchmark sizes.  Each run uses the full dataset")
    print(f"  but varies how many IDs are searched.  Two non-existent IDs")
    print(f"  are added to each run to test worst-case linear search.")
    print(f"  {THN}")

    # Benchmark sizes (label, num_searches) 
    benchmarks = [
        ("20 searches  (assignment min)",        20),
        ("100 searches (small scale)",          100),
        ("500 searches (medium scale)",         500),
        (f"{len(transactions)} searches (full dataset)", len(transactions)),
    ]

    all_results = []
    for label, n in benchmarks:
        result = run_benchmark(transactions, num_searches=n)
        print_single_result(result, label)
        all_results.append(result)

    labels = [b[0] for b in benchmarks]
    print_summary_table(all_results, labels)