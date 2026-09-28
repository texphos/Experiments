#!/usr/bin/env python3
"""Reproducible unit-economics scenarios for Hearthday (python3 docs/economics.py).

Every input below is an ASSUMPTION unless marked VERIFIED; see docs/pricing-and-economics.md.
"""

PRICE_USD = 9.99                # proposed one-time Pro price (assumption; to be tested)
APPLE_COMMISSION = 0.15         # VERIFIED: App Store Small Business Program rate (developer.apple.com, 2026-09-28)
TAX_DRAG = 0.08                 # assumption: blended VAT/GST withheld before proceeds outside the US
APPLE_DEV_PROGRAM_PER_YEAR = 99 # assumption from a third-party fee guide; confirm on developer.apple.com (not paid)
OTHER_FIXED_PER_MONTH = 0       # no servers, no analytics, no paid services by design

net_per_sale = PRICE_USD * (1 - TAX_DRAG) * (1 - APPLE_COMMISSION)
fixed_per_month = APPLE_DEV_PROGRAM_PER_YEAR / 12 + OTHER_FIXED_PER_MONTH

scenarios = [
    # name, monthly downloads, download-to-Pro conversion
    ("Low", 300, 0.02),
    ("Base", 1_500, 0.04),
    ("High", 5_000, 0.07),
]

print(f"Net proceeds per sale ≈ ${net_per_sale:.2f} (price ${PRICE_USD}, {APPLE_COMMISSION:.0%} commission, {TAX_DRAG:.0%} tax drag)")
print(f"Fixed cost ≈ ${fixed_per_month:.2f}/month → break-even at {fixed_per_month / net_per_sale:.1f} sales/month\n")
print(f"{'Scenario':<8} {'Downloads/mo':>12} {'Conv.':>6} {'Sales/mo':>9} {'Net/mo':>9} {'Net/yr':>10}")
for name, downloads, conv in scenarios:
    sales = downloads * conv
    net = sales * net_per_sale - fixed_per_month
    print(f"{name:<8} {downloads:>12,} {conv:>6.0%} {sales:>9.0f} {net:>9,.0f} {net * 12:>10,.0f}")

print("\nMax affordable cost per install if paid ads had to break even on the first purchase:")
for name, _, conv in scenarios:
    print(f"  {name:<5} {conv:.0%} conversion → ${net_per_sale * conv:.2f} per install")

print("\nPrice sensitivity (Base downloads and conversion held fixed; conversion would in reality move with price):")
for price in (4.99, 6.99, 9.99, 14.99, 19.99):
    n = price * (1 - TAX_DRAG) * (1 - APPLE_COMMISSION)
    print(f"  ${price:>5}: ${1_500 * 0.04 * n - fixed_per_month:>7,.0f}/month")
