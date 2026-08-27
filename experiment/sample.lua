local function total(items, discount, tax_rate)
  local subtotal = 0
  for _, item in ipairs(items) do
    subtotal = subtotal + item.price
  end

  local discounted = subtotal - discount
  local tax = discounted * tax_rate
  return discounted + tax
end

return total
