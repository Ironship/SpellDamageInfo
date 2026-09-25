-- Small helpers shared by the tests. Run the tests from the repository root.

local T = { failures = 0, checks = 0 }

function T.loadAddonFile(path, ns)
  local chunk, err = loadfile(path)
  if not chunk then error(err, 2) end
  return chunk("SpellDamageInfo", ns)
end

function T.readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

function T.check(ok, label)
  T.checks = T.checks + 1
  if not ok then
    T.failures = T.failures + 1
    print("FAIL " .. label)
  end
  return ok
end

function T.eq(got, want, label)
  local ok = got == want
  if not ok and type(got) == "number" and type(want) == "number" then ok = math.abs(got - want) < 1e-6 end
  return T.check(ok, ("%s: got %s, want %s"):format(label, tostring(got), tostring(want)))
end

function T.finish(name)
  print(("%s: %d checks, %d failed"):format(name, T.checks, T.failures))
  if T.failures > 0 then os.exit(1) end
end

return T
