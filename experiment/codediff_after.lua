local function total(items, discount, tax_rate)
  assert(type(items) == "table", "items must be a table")
  assert(type(discount) == "number", "discount must be numeric")
  assert(type(tax_rate) == "number", "tax_rate must be numeric")

  local subtotal = 0
  for _, item in ipairs(items) do
    subtotal = subtotal + item.price
  end

  if subtotal == 0 then
    return 0
  end

  local discounted = subtotal - discount
  local tax = discounted * tax_rate
  return discounted + tax
end

return total
