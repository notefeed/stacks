-- Container logs from Docker's json-file logs, for VictoriaLogs; the same file serves products-1 (here) and gewerbe-1
-- (MarcelBruckner-Business/stacks' collectors): keep the two copies the same. Each line gets the stream fields Alloy gave it in Loki, so the dashboards' filters stay:
--   host       this server (HOST_NAME)
--   container  the container's name, from its config.v2.json next to its log (cached per id)
--   product    PRODUCT; on products-1 the container's Compose project when it is one of PRODUCT_PROJECTS; a Caddy line the
--              product of the site it served, from SITE_PRODUCTS ("<name>=<product> ..."), as Alloy's per-site match did
-- and the line's own JSON `level`, so Grafana colours it. Credentials in URLs and `password=`-style pairs are redacted (the
-- homelab's rules, its #372). Ported from the homelab's stacks/fluent-bit/shape.lua.
local HOST = os.getenv("HOST_NAME") or "unknown"
local PRODUCT = os.getenv("PRODUCT") or "unknown"

local SITES = {}
for name, product in (os.getenv("SITE_PRODUCTS") or ""):gmatch("([^%s=]+)=([^%s]+)") do
  SITES[name] = product
end
local PROJECTS = {}
for p in (os.getenv("PRODUCT_PROJECTS") or ""):gmatch("[^%s|,]+") do
  PROJECTS[p] = true
end

local cache = {}
local function container(path)
  local id = path and path:match("/containers/(%x+)/")
  if not id then return nil end
  local c = cache[id]
  if c then return c end
  local f = io.open("/var/lib/docker/containers/" .. id .. "/config.v2.json")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  local name = s:match('"Name":"/([^"]+)"')
  if not name then return nil end
  local project = s:match('"com%.docker%.compose%.project":"([^"]+)"')
  c = {name = name, product = (project and PROJECTS[project]) and project or PRODUCT}
  cache[id] = c
  return c
end

local KEYS = {"[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]", "[Pp][Aa][Ss][Ss][Ww][Dd]", "[Pp][Ww][Dd]"}
local function redact(m)
  for _, k in ipairs(KEYS) do
    m = m:gsub("(" .. k .. "=)[^&%s\"'#]+", "%1REDACTED")
  end
  return (m:gsub("(%a[%w+%.%-]*://[^:/@%s\"']+:)[^@/%s\"']+@", "%1REDACTED@"))
end

function docker(tag, ts, r)
  local m = redact((r["log"] or ""):gsub("\n$", ""))
  local c = container(r["filepath"]) or {name = "unknown", product = PRODUCT}
  local product = c.product
  if c.name == "caddy" then
    local site = m:match('"host":"([^"]+)"')
    if site and SITES[site] then product = SITES[site] end
  end
  return 2, ts, {_msg = m, host = HOST, container = c.name, product = product, stream = r["stream"],
                 level = m:match('"level"%s*:%s*"([^"]+)"')}
end
