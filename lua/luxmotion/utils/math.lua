local M = {}

function M.lerp(a, b, t)
  return a + (b - a) * t
end

function M.ease_out_quad(t)
  return 1 - (1 - t) * (1 - t)
end

function M.ease_in_quad(t)
  return t * t
end

function M.ease_in_out_quad(t)
  if t < 0.5 then
    return 2 * t * t
  else
    return 1 - 2 * (1 - t) * (1 - t)
  end
end

function M.get_easing_function(easing_type)
  if easing_type == "linear" then
    return function(t) return t end
  elseif easing_type == "ease-in" then
    return M.ease_in_quad
  elseif easing_type == "ease-out" then
    return M.ease_out_quad
  elseif easing_type == "ease-in-out" then
    return M.ease_in_out_quad
  else
    return function(t) return t end
  end
end

return M