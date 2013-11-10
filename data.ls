require "isf"
io = require "socket.io"
mongoose = require "mongoose"
Utils = require "../src/classes/helpers/EncodingUtils"
# mongoose.set 'debug', true

user-data-save-schema = mongoose.Schema {
	'host': String
	'ip': String
	'click-data': Object
	'hover-data': Object
	'scroll-data': Object
	'move-data': Object
}

user-data-save-schema.methods.decode-data = (data) ->
	data = Utils.decode-data data
	@normalize \hover, data.hover
	@normalize \click, data.click
	@normalize \scroll, data.scroll
	@normalize \move, data.move

user-data-save-schema.methods.normalize = (what, data) ->
	for key, value of data when key isnt "NaN,NaN"
		@["#{what}-data"] ?= {}; init = @["#{what}-data"][key]
		unless init then init = 0
		@["#{what}-data"][key] = (parseInt(init) + parseInt(value)) or 0


user-data-save-schema.methods.encode-data = -> Utils.encode-data hover: @["hover-data"], click: @["click-data"], scroll: @["scroll-data"], move: @['move-data']


class DataServer extends IS.Object
	(@app, @compiler, @server) ~>
		mongoose.connect "mongodb://localhost/itrackr"
		@data-server = io.listen @server
		@data-server.set 'log level', 1
		@UserData = mongoose.model "datadump", user-data-save-schema
		@data-server.sockets.on "connection" (sock) ~>
			count = 0
			sock.on 'begin', ~>
				sock.host = it.host
				@UserData.find {"host": it.host, "ip": sock.handshake.address.address}, (err, data) ~>
					sock.model = new @UserData host: it.host, ip: sock.handshake.address.address
					unless err or data.length is 0
						sock.model['click-data'] = data[0]['click-data'] or {}
						sock.model['hover-data'] = data[0]['hover-data'] or {}
						sock.model['scroll-data'] = data[0]['scroll-data'] or {}
						sock.model['move-data'] = data[0]['move-data'] or {}
			sock.on 'sendData', ~>
				unless not sock.model
					data = Utils.decode-data it
					old = sock.model
					sock.model = new @UserData host: old.host, ip: old.ip
					sock.model.normalize \hover, old['data-hover']
					sock.model.normalize \hover, data.hover
					sock.model.normalize \click, old['data-click']
					sock.model.normalize \click, data.click
					sock.model.normalize \scroll, old['data-click']
					sock.model.normalize \scroll, data.scroll
					sock.model.normalize \move, old['data-move']
					sock.model.normalize \move, data.move
					sock.model.save!
			sock.on 'requestData', (ip) ~>
				config = host: sock.host

				if ip isnt 'aggregated' then config.ip = ip
				final = new @UserData config

				@UserData.find config, (err, data) ~>
					if err or data.length is 0 then msg = "404"
					else 
						for item in data then let i = item
							[\click \scroll \move \hover].map ~>
								# final.normalize it, (i['#{it}-data'] or {})
								final["#{it}-data"] ?= {}; i["#{it}-data"] ?= {}
								final["#{it}-data"] = @join final["#{it}-data"], i["#{it}-data"]
						msg = final.encode-data!
					sock.emit "receiveData", data: msg
			sock.on "requestIPs", ~>
				@UserData.find {host: sock.host}, (err, data) ~>
					if err or data.length is 0 then msg = "404"
					else
						ips = []
						for item in data when not (item.ip in ips)
							ips.push item.ip
						sock.emit "receiveIPs", ips

			sock.on "disconnect", ~>
				if sock.model then sock.model.save!
	join: (a, b) ~>
		for key, value of a when key.match "[0-9]+,[0-9]+"
			if b[key]? then b[key] += value
			else b[key] = value
		b


module.exports = DataServer