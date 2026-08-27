# Betwixt review

file: sample.lua

## Comment

range: 7-9
author: human
status: open
type: question
anchor:
      local discounted = subtotal - discount
      local tax = discounted * tax_rate
      return discounted + tax
body:
Should discounts larger than the subtotal be rejected or clamped? The current calculation can return a negative total.
If negative totals are intentional, the behavior should be documented for callers.
Otherwise, consider rejecting or clamping the discount before calculating tax.

## Comment

range: 3-4
author: agent
status: open
type: risk
anchor:
      for _, item in ipairs(items) do
        subtotal = subtotal + item.price
body:
An item without a numeric `price` will fail inside this loop. If validation belongs to the caller, that contract should be explicit.
