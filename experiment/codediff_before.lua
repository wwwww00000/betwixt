local function total(items, discount, tax_rate)
  local subtotal = 0
  local legacy_item_count = #items
  for _, item in ipairs(items) do
    subtotal = subtotal + item.price
  end

  local legacy_service_fee = legacy_item_count > 5 and 2 or 0
  if legacy_service_fee > 0 then
    subtotal = subtotal + legacy_service_fee
  end

  local discounted = subtotal - discount
  local tax = discounted * tax_rate
  return discounted + tax
end

local function legacy_summary(items)
  return "items: " .. #items
end

return total
