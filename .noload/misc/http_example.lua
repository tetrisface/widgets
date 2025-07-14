local function url_escape(str)
	return (str:gsub('[^%w%-._~]', function(c)
		return string.format('%%%02X', string.byte(c))
	end))
end
local function fetch_http_proxy(url)
	local host = 'api.allorigins.win'
	local path = '/raw?url=' .. url_escape(url)

	local tcp = assert(socket.tcp())
	assert(tcp:connect(host, 80))
	tcp:send(
		'GET ' .. path .. ' HTTP/1.1\r\n'
			.. 'Host: ' .. host .. '\r\n'
			.. 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36\r\n'
			.. 'Connection: close\r\n\r\n'
	)

	local headers_done = false
	local content = {}

	while true do
		local line, err = tcp:receive('*l')
		if not line then
			break
		end
		if headers_done then
			table.insert(content, line)
		elseif line == '' then
			headers_done = true
		end
	end

	tcp:close()
	return table.concat(content, '\n')
end
