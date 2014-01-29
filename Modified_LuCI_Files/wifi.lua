--[[
LuCI - Lua Configuration Interface

Copyright 2008 Steven Barth <steven@midlink.org>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: wifi.lua 9414 2012-10-31 15:58:15Z dgolle $
]]--

local wa = require "luci.tools.webadmin"
local nw = require "luci.model.network"
local ut = require "luci.util"
local nt = require "luci.sys".net
local fs = require "nixio.fs"

arg[1] = arg[1] or ""

m = Map("wireless", "",
	translate("The <em>Device Configuration</em> section covers physical settings of the radio " ..
		"hardware such as channel, transmit power or antenna selection which is shared among all " ..
		"defined wireless networks (if the radio hardware is multi-SSID capable). Per network settings " ..
		"like encryption or operation mode are grouped in the <em>Interface Configuration</em>."))

m:chain("network")
m:chain("firewall")

local ifsection

function m.on_commit(map)
	local wnet = nw:get_wifinet(arg[1])
	if ifsection and wnet then
		ifsection.section = wnet.sid
		m.title = luci.util.pcdata(wnet:get_i18n())
	end
end

nw.init(m.uci)

local wnet = nw:get_wifinet(arg[1])
local wdev = wnet and wnet:get_device()

-- redirect to overview page if network does not exist anymore (e.g. after a revert)
if not wnet or not wdev then
	luci.http.redirect(luci.dispatcher.build_url("admin/network/wireless"))
	return
end

-- wireless toggle was requested, commit and reload page
function m.parse(map)
	if m:formvalue("cbid.wireless.%s.__toggle" % wdev:name()) then
		if wdev:get("disabled") == "1" or wnet:get("disabled") == "1" then
			wnet:set("disabled", nil)
		else
			wnet:set("disabled", "1")
		end
		wdev:set("disabled", nil)

		nw:commit("wireless")
		luci.sys.call("(env -i /sbin/wifi down; env -i /sbin/wifi up) >/dev/null 2>/dev/null")

		luci.http.redirect(luci.dispatcher.build_url("admin/network/wireless", arg[1]))
		return
	end
	Map.parse(map)
end

m.title = luci.util.pcdata(wnet:get_i18n())


local function txpower_list(iw)
	local list = iw.txpwrlist or { }
	local off  = tonumber(iw.txpower_offset) or 0
	local new  = { }
	local prev = -1
	local _, val
	for _, val in ipairs(list) do
		local dbm = val.dbm + off
		local mw  = math.floor(10 ^ (dbm / 10))
		if mw ~= prev then
			prev = mw
			new[#new+1] = {
				display_dbm = dbm,
				display_mw  = mw,
				driver_dbm  = val.dbm,
				driver_mw   = val.mw
			}
		end
	end
	return new
end

local function txpower_current(pwr, list)
	pwr = tonumber(pwr)
	if pwr ~= nil then
		local _, item
		for _, item in ipairs(list) do
			if item.driver_dbm >= pwr then
				return item.driver_dbm
			end
		end
	end
	return (list[#list] and list[#list].driver_dbm) or pwr or 0
end

local iw = luci.sys.wifi.getiwinfo(arg[1])
local hw_modes      = iw.hwmodelist or { }
local tx_power_list = txpower_list(iw)
local tx_power_cur  = txpower_current(wdev:get("txpower"), tx_power_list)

s = m:section(NamedSection, wdev:name(), "wifi-device", translate("Device Configuration"))
s.addremove = false

s:tab("general", translate("General Setup"))
s:tab("macfilter", translate("MAC-Filter"))
s:tab("advanced", translate("Advanced Settings"))

--[[
back = s:option(DummyValue, "_overview", translate("Overview"))
back.value = ""
back.titleref = luci.dispatcher.build_url("admin", "network", "wireless")
]]

st = s:taboption("general", DummyValue, "__status", translate("Status"))
st.template = "admin_network/wifi_status"
st.ifname   = arg[1]

en = s:taboption("general", Button, "__toggle")

if wdev:get("disabled") == "1" or wnet:get("disabled") == "1" then
	en.title      = translate("Wireless network is disabled")
	en.inputtitle = translate("Enable")
	en.inputstyle = "apply"
else
	en.title      = translate("Wireless network is enabled")
	en.inputtitle = translate("Disable")
	en.inputstyle = "reset"
end


local hwtype = wdev:get("type")
local htcaps = wdev:get("ht_capab") and true or false

-- NanoFoo
local nsantenna = wdev:get("antenna")

-- Check whether there is a client interface on the same radio,
-- if yes, lock the channel choice as the station will dicatate the freq
local has_sta = nil
local _, net
for _, net in ipairs(wdev:get_wifinets()) do
	if net:mode() == "sta" and net:id() ~= wnet:id() then
		has_sta = net
		break
	end
end

if has_sta then
	ch = s:taboption("general", DummyValue, "choice", translate("Channel"))
	ch.value = translatef("Locked to channel %d used by %s",
		has_sta:channel(), has_sta:shortname())
else
	ch = s:taboption("general", Value, "channel", translate("Channel"))
	ch:value("auto", translate("auto"))
	for _, f in ipairs(iw and iw.freqlist or { }) do
		if not f.restricted then
			ch:value(f.channel, "%i (%.3f GHz)" %{ f.channel, f.mhz / 1000 })
		end
	end
end

------------------- MAC80211 Device ------------------

if hwtype == "mac80211" then
	if #tx_power_list > 1 then
		tp = s:taboption("general", ListValue,
			"txpower", translate("Transmit Power"), "dBm")
		tp.rmempty = true
		tp.default = tx_power_cur
		function tp.cfgvalue(...)
			return txpower_current(Value.cfgvalue(...), tx_power_list)
		end

		for _, p in ipairs(tx_power_list) do
			tp:value(p.driver_dbm, "%i dBm (%i mW)"
				%{ p.display_dbm, p.display_mw })
		end
	end

	mode = s:taboption("advanced", ListValue, "hwmode", translate("Mode"))
	mode:value("", translate("auto"))
	if hw_modes.b then mode:value("11b", "802.11b") end
	if hw_modes.g then mode:value("11g", "802.11g") end
	if hw_modes.a then mode:value("11a", "802.11a") end

	if htcaps then
		if hw_modes.g and hw_modes.n then mode:value("11ng", "802.11g+n") end
		if hw_modes.a and hw_modes.n then mode:value("11na", "802.11a+n") end

		htmode = s:taboption("advanced", ListValue, "htmode", translate("HT mode"))
		htmode:depends("hwmode", "11na")
		htmode:depends("hwmode", "11ng")
		htmode:value("HT20", "20MHz")
		htmode:value("HT40-", translate("40MHz 2nd channel below"))
		htmode:value("HT40+", translate("40MHz 2nd channel above"))

		noscan = s:taboption("advanced", Flag, "noscan", translate("Force 40MHz mode"),
			translate("Always use 40MHz channels even if the secondary channel overlaps. Using this option does not comply with IEEE 802.11n-2009!"))
		noscan:depends("htmode", "HT40+")
		noscan:depends("htmode", "HT40-")
		noscan.default = noscan.disabled

		--htcapab = s:taboption("advanced", DynamicList, "ht_capab", translate("HT capabilities"))
		--htcapab:depends("hwmode", "11na")
		--htcapab:depends("hwmode", "11ng")
	end

	local cl = iw and iw.countrylist
	if cl and #cl > 0 then
		cc = s:taboption("advanced", ListValue, "country", translate("Country Code"), translate("Use ISO/IEC 3166 alpha2 country codes."))
		cc.default = tostring(iw and iw.country or "00")
		for _, c in ipairs(cl) do
			cc:value(c.alpha2, "%s - %s" %{ c.alpha2, c.name })
		end
	else
		s:taboption("advanced", Value, "country", translate("Country Code"), translate("Use ISO/IEC 3166 alpha2 country codes."))
	end

	s:taboption("advanced", Value, "distance", translate("Distance Optimization"),
		translate("Distance to farthest network member in meters."))

	-- external antenna profiles
	local eal = iw and iw.extant
	if eal and #eal > 0 then
		ea = s:taboption("advanced", ListValue, "extant", translate("Antenna Configuration"))
		for _, eap in ipairs(eal) do
			ea:value(eap.id, "%s (%s)" %{ eap.name, eap.description })
			if eap.selected then
				ea.default = eap.id
			end
		end
	end

	log_level = s:taboption("advanced", ListValue, "log_level", translate("Logging Level"))
	log_level.optional = true
	log_level:value("2", "Informational Message")
	log_level:value("0", "Verbose Debugging")
	log_level:value("1", "Debugging")
	log_level:value("3", "Notification")
	log_level:value("4", "Warning")

	beacon_int = s:taboption("advanced", Value, "beacon_int", translate("Beacon Interval"),"(15 - 65535)")
	beacon_int.optional = true
	beacon_int.placeholder = 100

end

----------------------- Interface -----------------------

s = m:section(NamedSection, wnet.sid, "wifi-iface", translate("Interface Configuration"))
ifsection = s
s.addremove = false
s.anonymous = true
s.defaults.device = wdev:name()

s:tab("general", translate("General Setup"))
s:tab("encryption", translate("Wireless Security"))
s:tab("macfilter", translate("MAC-Filter"))
s:tab("advanced", translate("Advanced Settings"))

s:taboption("general", Value, "ssid", translate("<abbr title=\"Extended Service Set Identifier\">ESSID</abbr>"))

mode = s:taboption("general", ListValue, "mode", translate("Mode"))
mode.override_values = true
mode:value("ap", translate("Access Point"))
mode:value("sta", translate("Client"))
mode:value("adhoc", translate("Ad-Hoc"))

bssid = s:taboption("general", Value, "bssid", translate("<abbr title=\"Basic Service Set Identifier\">BSSID</abbr>"))

network = s:taboption("general", Value, "network", translate("Network"),
	translate("Choose the network(s) you want to attach to this wireless interface or " ..
		"fill out the <em>create</em> field to define a new network."))

network.rmempty = true
network.template = "cbi/network_netlist"
network.widget = "checkbox"
network.novirtual = true

function network.write(self, section, value)
	local i = nw:get_interface(section)
	if i then
		if value == '-' then
			value = m:formvalue(self:cbid(section) .. ".newnet")
			if value and #value > 0 then
				local n = nw:add_network(value, {proto="none"})
				if n then n:add_interface(i) end
			else
				local n = i:get_network()
				if n then n:del_interface(i) end
			end
		else
			local v
			for _, v in ipairs(i:get_networks()) do
				v:del_interface(i)
			end
			for v in ut.imatch(value) do
				local n = nw:get_network(v)
				if n then
					if not n:is_empty() then
						n:set("type", "bridge")
					end
					n:add_interface(i)
				end
			end
		end
	end
end

-------------------- MAC80211 Interface ----------------------

if hwtype == "mac80211" then
	if fs.access("/usr/sbin/iw") then
		mode:value("mesh", "802.11s")
	end

	mode:value("ahdemo", translate("Pseudo Ad-Hoc"))
	mode:value("monitor", translate("Monitor"))
	bssid:depends({mode="adhoc"})
	bssid:depends({mode="sta"})
	bssid:depends({mode="sta-wds"})

	mp = s:taboption("macfilter", ListValue, "macfilter", translate("MAC-Address Filter"))
	mp:depends({mode="ap"})
	mp:depends({mode="ap-wds"})
	mp:value("", translate("disable"))
	mp:value("allow", translate("Allow listed only"))
	mp:value("deny", translate("Allow all except listed"))

	ml = s:taboption("macfilter", DynamicList, "maclist", translate("MAC-List"))
	ml.datatype = "macaddr"
	ml:depends({macfilter="allow"})
	ml:depends({macfilter="deny"})
	nt.mac_hints(function(mac, name) ml:value(mac, "%s (%s)" %{ mac, name }) end)

	mode:value("ap-wds", "%s (%s)" % {translate("Access Point"), translate("WDS")})
	mode:value("sta-wds", "%s (%s)" % {translate("Client"), translate("WDS")})

	function mode.write(self, section, value)
		if value == "ap-wds" then
			ListValue.write(self, section, "ap")
			m.uci:set("wireless", section, "wds", 1)
		elseif value == "sta-wds" then
			ListValue.write(self, section, "sta")
			m.uci:set("wireless", section, "wds", 1)
		else
			ListValue.write(self, section, value)
			m.uci:delete("wireless", section, "wds")
		end
	end

	function mode.cfgvalue(self, section)
		local mode = ListValue.cfgvalue(self, section)
		local wds  = m.uci:get("wireless", section, "wds") == "1"

		if mode == "ap" and wds then
			return "ap-wds"
		elseif mode == "sta" and wds then
			return "sta-wds"
		else
			return mode
		end
	end

	hidden = s:taboption("general", Flag, "hidden", translate("Hide <abbr title=\"Extended Service Set Identifier\">ESSID</abbr>"))
	hidden:depends({mode="ap"})
	hidden:depends({mode="ap-wds"})

	wmm = s:taboption("general", Flag, "wmm", translate("WMM Mode"))
	wmm:depends({mode="ap"})
	wmm:depends({mode="ap-wds"})
	wmm.default = wmm.enabled

	short_preamble = s:taboption("general", Flag, "short_preamble", translate("Short Preamble"))
	short_preamble.default = short_preamble.enabled

	isolate = s:taboption("general", Flag, "isolate", translate("Wireless Client Isolation"))
	isolate.optional = true
	isolate:depends({mode="ap"})

	dtim_period = s:taboption("general", Value, "dtim_period", translate("DTIM Interval"),"Delivery Traffic Indication Message Interval")
	dtim_period.optional = true
	dtim_period.placeholder = 2

end

------------------- WiFI-Encryption -------------------

encr = s:taboption("encryption", ListValue, "encryption", translate("Encryption"))
encr.override_values = true
encr.override_depends = true
encr:depends({mode="ap"})
encr:depends({mode="sta"})
encr:depends({mode="adhoc"})
encr:depends({mode="ahdemo"})
encr:depends({mode="ap-wds"})
encr:depends({mode="sta-wds"})
encr:depends({mode="mesh"})

cipher = s:taboption("encryption", ListValue, "cipher", translate("Cipher"))
cipher:depends({encryption="wpa"})
cipher:depends({encryption="wpa2"})
cipher:depends({encryption="psk"})
cipher:depends({encryption="psk2"})
cipher:depends({encryption="wpa-mixed"})
cipher:depends({encryption="psk-mixed"})
cipher:value("auto", translate("auto"))
cipher:value("ccmp", translate("Force CCMP (AES)"))
cipher:value("tkip", translate("Force TKIP"))
cipher:value("tkip+ccmp", translate("Force TKIP and CCMP (AES)"))

function encr.cfgvalue(self, section)
	local v = tostring(ListValue.cfgvalue(self, section))
	if v == "wep" then
		return "wep-open"
	elseif v and v:match("%+") then
		return (v:gsub("%+.+$", ""))
	end
	return v
end

function encr.write(self, section, value)
	local e = tostring(encr:formvalue(section))
	local c = tostring(cipher:formvalue(section))
	if value == "wpa" or value == "wpa2"  then
		self.map.uci:delete("wireless", section, "key")
	end
	if e and (c == "tkip" or c == "ccmp" or c == "tkip+ccmp") then
		e = e .. "+" .. c
	end
	self.map:set(section, "encryption", e)
end

function cipher.cfgvalue(self, section)
	local v = tostring(ListValue.cfgvalue(encr, section))
	if v and v:match("%+") then
		v = v:gsub("^[^%+]+%+", "")
		if v == "aes" then v = "ccmp"
		elseif v == "tkip+aes" then v = "tkip+ccmp"
		elseif v == "aes+tkip" then v = "tkip+ccmp"
		elseif v == "ccmp+tkip" then v = "tkip+ccmp"
		end
	end
	return v
end

function cipher.write(self, section)
	return encr:write(section)
end


encr:value("none", "No Encryption")
encr:value("wep-open",   translate("WEP Open System"), {mode="ap"}, {mode="sta"}, {mode="ap-wds"}, {mode="sta-wds"}, {mode="adhoc"}, {mode="ahdemo"}, {mode="wds"})
encr:value("wep-shared", translate("WEP Shared Key"),  {mode="ap"}, {mode="sta"}, {mode="ap-wds"}, {mode="sta-wds"}, {mode="adhoc"}, {mode="ahdemo"}, {mode="wds"})

if hwtype == "atheros" or hwtype == "mac80211" or hwtype == "prism2" then
	local supplicant = fs.access("/usr/sbin/wpa_supplicant")
	local hostapd = fs.access("/usr/sbin/hostapd")

	-- Probe EAP support
	local has_ap_eap  = (os.execute("hostapd -veap >/dev/null 2>/dev/null") == 0)
	local has_sta_eap = (os.execute("wpa_supplicant -veap >/dev/null 2>/dev/null") == 0)

	if hostapd and supplicant then
		encr:value("psk", "WPA-PSK", {mode="ap"}, {mode="sta"}, {mode="ap-wds"}, {mode="sta-wds"})
		encr:value("psk2", "WPA2-PSK", {mode="ap"}, {mode="sta"}, {mode="ap-wds"}, {mode="sta-wds"})
		encr:value("psk-mixed", "WPA-PSK/WPA2-PSK Mixed Mode", {mode="ap"}, {mode="sta"}, {mode="ap-wds"}, {mode="sta-wds"})
		if has_ap_eap and has_sta_eap then
			encr:value("wpa", "WPA-EAP", {mode="ap"}, {mode="sta"}, {mode="ap-wds"}, {mode="sta-wds"})
			encr:value("wpa2", "WPA2-EAP", {mode="ap"}, {mode="sta"}, {mode="ap-wds"}, {mode="sta-wds"})
		end
	elseif hostapd and not supplicant then
		encr:value("psk", "WPA-PSK", {mode="ap"}, {mode="ap-wds"})
		encr:value("psk2", "WPA2-PSK", {mode="ap"}, {mode="ap-wds"})
		encr:value("psk-mixed", "WPA-PSK/WPA2-PSK Mixed Mode", {mode="ap"}, {mode="ap-wds"})
		if has_ap_eap then
			encr:value("wpa", "WPA-EAP", {mode="ap"}, {mode="ap-wds"})
			encr:value("wpa2", "WPA2-EAP", {mode="ap"}, {mode="ap-wds"})
		end
		encr.description = translate(
			"WPA-Encryption requires wpa_supplicant (for client mode) or hostapd (for AP " ..
			"and ad-hoc mode) to be installed."
		)
	elseif not hostapd and supplicant then
		encr:value("psk", "WPA-PSK", {mode="sta"}, {mode="sta-wds"})
		encr:value("psk2", "WPA2-PSK", {mode="sta"}, {mode="sta-wds"})
		encr:value("psk-mixed", "WPA-PSK/WPA2-PSK Mixed Mode", {mode="sta"}, {mode="sta-wds"})
		if has_sta_eap then
			encr:value("wpa", "WPA-EAP", {mode="sta"}, {mode="sta-wds"})
			encr:value("wpa2", "WPA2-EAP", {mode="sta"}, {mode="sta-wds"})
		end
		encr.description = translate(
			"WPA-Encryption requires wpa_supplicant (for client mode) or hostapd (for AP " ..
			"and ad-hoc mode) to be installed."
		)
	else
		encr.description = translate(
			"WPA-Encryption requires wpa_supplicant (for client mode) or hostapd (for AP " ..
			"and ad-hoc mode) to be installed."
		)
	end
end

auth_server = s:taboption("encryption", Value, "auth_server", translate("Radius-Authentication-Server"))
auth_server:depends({mode="ap", encryption="wpa"})
auth_server:depends({mode="ap", encryption="wpa2"})
auth_server:depends({mode="ap-wds", encryption="wpa"})
auth_server:depends({mode="ap-wds", encryption="wpa2"})
auth_server.rmempty = true
auth_server.datatype = "host"

auth_port = s:taboption("encryption", Value, "auth_port", translate("Radius-Authentication-Port"), translatef("Default %d", 1812))
auth_port:depends({mode="ap", encryption="wpa"})
auth_port:depends({mode="ap", encryption="wpa2"})
auth_port:depends({mode="ap-wds", encryption="wpa"})
auth_port:depends({mode="ap-wds", encryption="wpa2"})
auth_port.rmempty = true
auth_port.datatype = "port"

auth_secret = s:taboption("encryption", Value, "auth_secret", translate("Radius-Authentication-Secret"))
auth_secret:depends({mode="ap", encryption="wpa"})
auth_secret:depends({mode="ap", encryption="wpa2"})
auth_secret:depends({mode="ap-wds", encryption="wpa"})
auth_secret:depends({mode="ap-wds", encryption="wpa2"})
auth_secret.rmempty = true
auth_secret.password = true

acct_server = s:taboption("encryption", Value, "acct_server", translate("Radius-Accounting-Server"))
acct_server:depends({mode="ap", encryption="wpa"})
acct_server:depends({mode="ap", encryption="wpa2"})
acct_server:depends({mode="ap-wds", encryption="wpa"})
acct_server:depends({mode="ap-wds", encryption="wpa2"})
acct_server.rmempty = true
acct_server.datatype = "host"

acct_port = s:taboption("encryption", Value, "acct_port", translate("Radius-Accounting-Port"), translatef("Default %d", 1813))
acct_port:depends({mode="ap", encryption="wpa"})
acct_port:depends({mode="ap", encryption="wpa2"})
acct_port:depends({mode="ap-wds", encryption="wpa"})
acct_port:depends({mode="ap-wds", encryption="wpa2"})
acct_port.rmempty = true
acct_port.datatype = "port"

acct_secret = s:taboption("encryption", Value, "acct_secret", translate("Radius-Accounting-Secret"))
acct_secret:depends({mode="ap", encryption="wpa"})
acct_secret:depends({mode="ap", encryption="wpa2"})
acct_secret:depends({mode="ap-wds", encryption="wpa"})
acct_secret:depends({mode="ap-wds", encryption="wpa2"})
acct_secret.rmempty = true
acct_secret.password = true

wpakey = s:taboption("encryption", Value, "_wpa_key", translate("Key"))
wpakey:depends("encryption", "psk")
wpakey:depends("encryption", "psk2")
wpakey:depends("encryption", "psk+psk2")
wpakey:depends("encryption", "psk-mixed")
wpakey.datatype = "wpakey"
wpakey.rmempty = true
wpakey.password = true

wpakey.cfgvalue = function(self, section, value)
	local key = m.uci:get("wireless", section, "key")
	if key == "1" or key == "2" or key == "3" or key == "4" then
		return nil
	end
	return key
end

wpakey.write = function(self, section, value)
	self.map.uci:set("wireless", section, "key", value)
	self.map.uci:delete("wireless", section, "key1")
end


wepslot = s:taboption("encryption", ListValue, "_wep_key", translate("Used Key Slot"))
wepslot:depends("encryption", "wep-open")
wepslot:depends("encryption", "wep-shared")
wepslot:value("1", translatef("Key #%d", 1))
wepslot:value("2", translatef("Key #%d", 2))
wepslot:value("3", translatef("Key #%d", 3))
wepslot:value("4", translatef("Key #%d", 4))

wepslot.cfgvalue = function(self, section)
	local slot = tonumber(m.uci:get("wireless", section, "key"))
	if not slot or slot < 1 or slot > 4 then
		return 1
	end
	return slot
end

wepslot.write = function(self, section, value)
	self.map.uci:set("wireless", section, "key", value)
end

local slot
for slot=1,4 do
	wepkey = s:taboption("encryption", Value, "key" .. slot, translatef("Key #%d", slot))
	wepkey:depends("encryption", "wep-open")
	wepkey:depends("encryption", "wep-shared")
	wepkey.datatype = "wepkey"
	wepkey.rmempty = true
	wepkey.password = true

	function wepkey.write(self, section, value)
		if value and (#value == 5 or #value == 13) then
			value = "s:" .. value
		end
		return Value.write(self, section, value)
	end
end


if hwtype == "atheros" or hwtype == "mac80211" or hwtype == "prism2" then
	nasid = s:taboption("encryption", Value, "nasid", translate("NAS ID"))
	nasid:depends({mode="ap", encryption="wpa"})
	nasid:depends({mode="ap", encryption="wpa2"})
	nasid:depends({mode="ap-wds", encryption="wpa"})
	nasid:depends({mode="ap-wds", encryption="wpa2"})
	nasid.rmempty = true

	eaptype = s:taboption("encryption", ListValue, "eap_type", translate("EAP-Method"))
	eaptype:value("tls",  "TLS")
	eaptype:value("ttls", "TTLS")
	eaptype:value("peap", "PEAP")
	eaptype:depends({mode="sta", encryption="wpa"})
	eaptype:depends({mode="sta", encryption="wpa2"})
	eaptype:depends({mode="sta-wds", encryption="wpa"})
	eaptype:depends({mode="sta-wds", encryption="wpa2"})

	cacert = s:taboption("encryption", FileUpload, "ca_cert", translate("Path to CA-Certificate"))
	cacert:depends({mode="sta", encryption="wpa"})
	cacert:depends({mode="sta", encryption="wpa2"})
	cacert:depends({mode="sta-wds", encryption="wpa"})
	cacert:depends({mode="sta-wds", encryption="wpa2"})

	clientcert = s:taboption("encryption", FileUpload, "client_cert", translate("Path to Client-Certificate"))
	clientcert:depends({mode="sta", encryption="wpa"})
	clientcert:depends({mode="sta", encryption="wpa2"})
	clientcert:depends({mode="sta-wds", encryption="wpa"})
	clientcert:depends({mode="sta-wds", encryption="wpa2"})

	privkey = s:taboption("encryption", FileUpload, "priv_key", translate("Path to Private Key"))
	privkey:depends({mode="sta", eap_type="tls", encryption="wpa2"})
	privkey:depends({mode="sta", eap_type="tls", encryption="wpa"})
	privkey:depends({mode="sta-wds", eap_type="tls", encryption="wpa2"})
	privkey:depends({mode="sta-wds", eap_type="tls", encryption="wpa"})

	privkeypwd = s:taboption("encryption", Value, "priv_key_pwd", translate("Password of Private Key"))
	privkeypwd:depends({mode="sta", eap_type="tls", encryption="wpa2"})
	privkeypwd:depends({mode="sta", eap_type="tls", encryption="wpa"})
	privkeypwd:depends({mode="sta-wds", eap_type="tls", encryption="wpa2"})
	privkeypwd:depends({mode="sta-wds", eap_type="tls", encryption="wpa"})


	auth = s:taboption("encryption", Value, "auth", translate("Authentication"))
	auth:value("PAP")
	auth:value("CHAP")
	auth:value("MSCHAP")
	auth:value("MSCHAPV2")
	auth:depends({mode="sta", eap_type="peap", encryption="wpa2"})
	auth:depends({mode="sta", eap_type="peap", encryption="wpa"})
	auth:depends({mode="sta", eap_type="ttls", encryption="wpa2"})
	auth:depends({mode="sta", eap_type="ttls", encryption="wpa"})
	auth:depends({mode="sta-wds", eap_type="peap", encryption="wpa2"})
	auth:depends({mode="sta-wds", eap_type="peap", encryption="wpa"})
	auth:depends({mode="sta-wds", eap_type="ttls", encryption="wpa2"})
	auth:depends({mode="sta-wds", eap_type="ttls", encryption="wpa"})


	identity = s:taboption("encryption", Value, "identity", translate("Identity"))
	identity:depends({mode="sta", eap_type="peap", encryption="wpa2"})
	identity:depends({mode="sta", eap_type="peap", encryption="wpa"})
	identity:depends({mode="sta", eap_type="ttls", encryption="wpa2"})
	identity:depends({mode="sta", eap_type="ttls", encryption="wpa"})
	identity:depends({mode="sta-wds", eap_type="peap", encryption="wpa2"})
	identity:depends({mode="sta-wds", eap_type="peap", encryption="wpa"})
	identity:depends({mode="sta-wds", eap_type="ttls", encryption="wpa2"})
	identity:depends({mode="sta-wds", eap_type="ttls", encryption="wpa"})

	password = s:taboption("encryption", Value, "password", translate("Password"))
	password:depends({mode="sta", eap_type="peap", encryption="wpa2"})
	password:depends({mode="sta", eap_type="peap", encryption="wpa"})
	password:depends({mode="sta", eap_type="ttls", encryption="wpa2"})
	password:depends({mode="sta", eap_type="ttls", encryption="wpa"})
	password:depends({mode="sta-wds", eap_type="peap", encryption="wpa2"})
	password:depends({mode="sta-wds", eap_type="peap", encryption="wpa"})
	password:depends({mode="sta-wds", eap_type="ttls", encryption="wpa2"})
	password:depends({mode="sta-wds", eap_type="ttls", encryption="wpa"})
end

return m
