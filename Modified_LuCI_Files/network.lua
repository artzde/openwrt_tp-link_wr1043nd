--[[
LuCI - Lua Configuration Interface

Copyright 2008 Steven Barth <steven@midlink.org>
Copyright 2008 Jo-Philipp Wich <xm@leipzig.freifunk.net>

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

	http://www.apache.org/licenses/LICENSE-2.0

$Id: network.lua 9849 2013-06-24 12:00:29Z Cyrus $
]]--

local fs = require "nixio.fs"

m = Map("network", translate("Interfaces"))
m.pageaction = false
m:section(SimpleSection).template = "admin_network/iface_overview"

local network = require "luci.model.network"
if network:has_ipv6() then
	local s = m:section(NamedSection, "globals", "globals", translate("Global network options"))
	local o = s:option(Value, "ula_prefix", translate("IPv6 ULA-Prefix"))
	o.datatype = "ip6addr"
	o.rmempty = true
	m.pageaction = true
end


return m
