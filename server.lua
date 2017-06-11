
server = {}

function server.start(port)
	logger.log('Starting server on port ' .. port)
	server.udp = socket.udp()
	server.udp:settimeout(0)
	server.udp:setsockname('*', port)
	server.chatLog = {}
	server.players = {}
	server.ip2id = {}
	server.lastUpdate = 0
	server.updateRate = 1/20
end

function server.addPlayer(id, ip, port)
	server.players[id] = {
		connection = {ip = ip, port = port},
		lastUpdate = time
	}
	setPlayerVals(server.players[id], {
		x = 1260, y = 1000, direction = 1,
		anim = {
			state = 'jump',
			frame = 8
		},
		grapple = {
			on = false, x = 0, y = 0
		},
		holdingStaff = false
	})
	server.ip2id[ip .. ':' .. port] = id
	server.added = server.added or {}
	server.added.players = server.added.players or {}
	server.added.players[id] = {}
	setPlayerVals(server.added.players[id], server.players[id])
	local dg = string.format('%s %s', 'returnPlayerID', id)
	server.udp:sendto(dg, ip, port)
	dg = string.format('%s %s %s', 'chatMsg', 'Server', id .. ' connected')
	for k, v in pairs(server.players) do
		server.udp:sendto(dg, v.connection.ip, v.connection.port)
	end
end

function server.removePlayer(id)
	local v = server.players[id]
	server.ip2id[v.connection.ip .. ':' .. v.connection.port] = nil
	server.players[id] = nil
	server.removed = server.removed or {}
	server.removed.players = server.removed.players or {}
	server.removed.players[id] = true
	local dg = string.format('%s %s %s', 'chatMsg', 'Server', id .. ' disconnected')
	for k, v in pairs(server.players) do
		server.udp:sendto(dg, v.connection.ip, v.connection.port)
	end
	logger.log('removed')
end

function server.update(dt)
	repeat
		local data, msg_or_ip, port_or_nil = server.udp:receivefrom()
		local id = server.ip2id[msg_or_ip .. ':' .. tostring(port_or_nil)]
		if id then
			server.players[id].lastUpdate = time
		end
		if data then
			local cmd, cmdParams = data:match('^(%S*) (.*)')
			if cmd == 'requestPlayer' then
				id = cmdParams:match('^(%S*)')
				local postfix = 0
				while server.players[buildID(id, postfix)] or buildID(id, postfix) == 'Server' do
					postfix = postfix + 1
				end
				local fullID = buildID(id, postfix)
				server.addPlayer(fullID, msg_or_ip, port_or_nil)
				local add = {players={}}
				for k, v in pairs(server.players) do
					add.players[k] = {}
					setPlayerVals(add.players[k], v)
				end
				local dg = string.format('%s %s', 'add', json.encode(add))
				server.udp:sendto(dg, msg_or_ip, port_or_nil)
			elseif id then
				if cmd == 'chatMsg' then
					local dg = string.format('%s %s %s', 'chatMsg', id, cmdParams)
					for k, v in pairs(server.players) do
						server.udp:sendto(dg, v.connection.ip, v.connection.port)
					end
				elseif cmd == 'setPlayer' then
					local pClient
					if pcall(function() pClient = json.decode(cmdParams) end) then
						local pServer = server.players[id]
						if pServer then
							setPlayerVals(pServer, pClient)
						end
					end
				elseif cmd == 'removePlayer' then
					server.removePlayer(id)
				end
			end
		elseif msg_or_ip ~= 'timeout' then
			logger.log('Network error: ' .. tostring(msg_or_ip))
		end
	until not data
	for k, v in pairs(server.players) do
		if time - v.lastUpdate > 5 then
			server.removePlayer(k)
		end
	end
	if time - server.lastUpdate > server.updateRate then
		server.lastUpdate = time
		local stateUpdate = {players={}}
		for k, v in pairs(server.players) do
			stateUpdate.players[k] = {}
			setPlayerVals(stateUpdate.players[k], v)
		end
		local dgStateUpdate = string.format('%s %s', 'stateUpdate', json.encode(stateUpdate))
		local dgAdd
		if server.added then
			dgAdd = string.format('%s %s', 'add', json.encode(server.added))
			server.added = nil
		end
		local dgRemove
		if server.removed then
			dgRemove = string.format('%s %s', 'remove', json.encode(server.removed))
			server.removed = nil
		end
		for k, v in pairs(server.players) do
			server.udp:sendto(dgStateUpdate, v.connection.ip, v.connection.port)
			if dgAdd then
				server.udp:sendto(dgAdd, v.connection.ip, v.connection.port)
			end
			if dgRemove then
				server.udp:sendto(dgRemove, v.connection.ip, v.connection.port)
			end
		end
	end
end
