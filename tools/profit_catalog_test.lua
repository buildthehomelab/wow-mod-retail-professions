-- Focused protocol/economics tests, Lua 5.1 compatible. No game client required.
local now, timers, sent, event = 0, {}, {}, nil
local updates = 0
local function advance(dt)
 now = now + dt
 for _ = 1, 100 do
  local found
  for i, t in ipairs(timers) do
   if t.at <= now then table.remove(timers, i); t.fn(); found = true; break end
  end
  if not found then break end
 end
end
GetTime = function () return now end
UnitName = function () return 'Tester' end
GetItemInfo = function () return nil end
wipe = function(t) for k in pairs(t) do t[k] = nil end end
bit = { band = function(a,b) return math.floor(a / b) % 2 * b end }
CreateFrame = function() return { RegisterEvent=function() end, SetScript=function(_,_,fn) event=fn end } end
SendAddonMessage = function(_,msg) assert(#msg <= 255); sent[#sent+1]=msg end
RetailProfessions = { Model={}, HaveCount=function() return 0 end,
 After=function(dt,fn) timers[#timers+1]={at=now+dt,fn=fn} end,
 Debounce=function(_,_,fn) fn() end, Fire=function() updates=updates+1 end, On=function() end }
assert(loadfile((arg[1] or 'addon/RetailProfessions')..'/Profit.lua'))()
local P=RetailProfessions.Profit
local function reply(code, req, rest) event(nil,nil,'RAH',code..':'..req..(rest and ':'..rest or ''),nil,'Tester') end
local function reqOf(msg) return msg:match('^[^:]+:([^:]+):') end
local entries={}
for i=1,95 do entries[i]=10000000+i end
P.Fetch(entries)
assert(#sent==1 and sent[1]:match('^KC:'), 'initial request must use catalog, one batch in flight')
local first=reqOf(sent[1])
reply('KR',first,'7.5:14')
reply('KD',first,'10000001,0,0,0,500,10,0,0,0,1000;10000002,0,0,0,0,10,0,0,0,200;10000003,0,0,0,0,15,0,0,1,9999;10000004,0,0,0,0,25,0,0,2,9999')
reply('KE',first)
assert(P.cut==7.5)
local value,how=P.SellValue(10000001)
assert(value==925 and how=='catalog', 'catalog output must deduct effective cut')
local cost,source=P.BuyCost(10000001)
assert(cost==500 and source=='vendor', 'vendor materials must win when cheaper')
assert(P.BuyCost(10000002)==200)
assert(P.BuyCost(10000003)==nil, 'locked reference cannot become a source')
assert(P.SellValue(10000004)==25, 'soulbound must remain vendor-only')
local a=P.Of({item=10000001,reagents={{id=10000002,n=2}},madeMin=2,madeMax=2})
assert(a.costKnown and a.cost==400 and a.profit==1450, 'multi-output craft economics')
assert(P.MarketText(10000001):find('availability and sale not guaranteed',1,true))
assert(P.Fetching(), 'remaining batches must remain pending')
advance(.13)
assert(#sent==2, 'one next batch after completion')
local second=reqOf(sent[2])
reply('ERR',second,'unknown')
assert(#sent==3 and sent[3]:match('^K:'), 'legacy server must fall back')
reply('KR',second,'5:14'); reply('KE',second)
advance(.13)
assert(#sent==4 and sent[4]:match('^K:'), 'queued requests must inherit negotiated fallback')
-- Timeout releases in-flight entries and progresses the queue rather than a permanent spinner.
local beforeUpdates = updates
advance(7)
advance(.13)
-- Finish any final batch too: all stalled requests must eventually release the spinner.
advance(7)
assert(not P.Fetching() and updates > beforeUpdates, 'terminal timeout must notify UI and clear loading')
local beforeSent = #sent
P.Fetch(entries)
assert(#sent == beforeSent, 'failed entries need cooldown, not an immediate redraw retry loop')
assert(P.state=='ok', 'one lost request must not erase valid catalog')
print('profit catalog tests passed: estimates, fees, vendor, gates, batching, fallback, timeout')
