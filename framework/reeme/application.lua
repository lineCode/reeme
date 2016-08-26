local configs = nil

local error_old = error
function error(e)
	error_old({ msg = e })
end

--print is use writes argument values into the nginx error.log file with the ngx.NOTICE log level
		
local baseapi = {
	statusCode = {
		HTTP_CONTINUE = ngx.HTTP_CONTINUE, --100
		HTTP_SWITCHING_PROTOCOLS = ngx.HTTP_SWITCHING_PROTOCOLS, --101
		HTTP_OK = ngx.HTTP_OK, --200
		HTTP_CREATED = ngx.HTTP_CREATED, --201
		HTTP_ACCEPTED = ngx.HTTP_ACCEPTED, --202
		HTTP_NO_CONTENT = ngx.HTTP_NO_CONTENT, --204
		HTTP_PARTIAL_CONTENT = ngx.HTTP_PARTIAL_CONTENT, --206
		HTTP_SPECIAL_RESPONSE = ngx.HTTP_SPECIAL_RESPONSE, --300
		HTTP_MOVED_PERMANENTLY = ngx.HTTP_MOVED_PERMANENTLY, --301
		HTTP_MOVED_TEMPORARILY = ngx.HTTP_MOVED_TEMPORARILY, --302
		HTTP_SEE_OTHER = ngx.HTTP_SEE_OTHER, --303
		HTTP_NOT_MODIFIED = ngx.HTTP_NOT_MODIFIED, --304
		HTTP_TEMPORARY_REDIRECT = ngx.HTTP_TEMPORARY_REDIRECT, --307
		HTTP_BAD_REQUEST = ngx.HTTP_BAD_REQUEST, --400
		HTTP_UNAUTHORIZED = ngx.HTTP_UNAUTHORIZED, --401
		HTTP_PAYMENT_REQUIRED = ngx.HTTP_PAYMENT_REQUIRED, --402
		HTTP_FORBIDDEN = ngx.HTTP_FORBIDDEN, --403
		HTTP_NOT_FOUND = ngx.HTTP_NOT_FOUND, --404
		HTTP_NOT_ALLOWED = ngx.HTTP_NOT_ALLOWED, --405
		HTTP_NOT_ACCEPTABLE = ngx.HTTP_NOT_ACCEPTABLE, --406
		HTTP_REQUEST_TIMEOUT = ngx.HTTP_REQUEST_TIMEOUT, --408
		HTTP_CONFLICT = ngx.HTTP_CONFLICT, --409
		HTTP_GONE = ngx.HTTP_GONE, --410
		HTTP_UPGRADE_REQUIRED = ngx.HTTP_UPGRADE_REQUIRED, --426
		HTTP_TOO_MANY_REQUESTS = ngx.HTTP_TOO_MANY_REQUESTS, --429
		HTTP_CLOSE = ngx.HTTP_CLOSE, --444
		HTTP_ILLEGAL = ngx.HTTP_ILLEGAL, --451
		HTTP_INTERNAL_SERVER_ERROR = ngx.HTTP_INTERNAL_SERVER_ERROR, --500
		HTTP_METHOD_NOT_IMPLEMENTED = ngx.HTTP_METHOD_NOT_IMPLEMENTED, --501
		HTTP_BAD_GATEWAY = ngx.HTTP_BAD_GATEWAY, --502
		HTTP_GATEWAY_TIMEOUT = ngx.HTTP_GATEWAY_TIMEOUT, --504
		HTTP_VERSION_NOT_SUPPORTED = ngx.HTTP_SERVICE_UNAVAILABLE, --505
		HTTP_INSUFFICIENT_STORAGE = ngx.HTTP_INSUFFICIENT_STORAGE, --507
	},
	
	method = {
		HTTP_GET = ngx.HTTP_GET,
		HTTP_HEAD = ngx.HTTP_HEAD,
		HTTP_PUT = ngx.HTTP_PUT,
		HTTP_POST = ngx.HTTP_POST,
		HTTP_DELETE = ngx.HTTP_DELETE,
		HTTP_OPTIONS = ngx.HTTP_OPTIONS,
		HTTP_MKCOL = ngx.HTTP_MKCOL,
		HTTP_COPY = ngx.HTTP_COPY,
		HTTP_MOVE = ngx.HTTP_MOVE,
		HTTP_PROPFIND = ngx.HTTP_PROPFIND,
		HTTP_PROPPATCH = ngx.HTTP_PROPPATCH,
		HTTP_LOCK = ngx.HTTP_LOCK,
		HTTP_UNLOCK = ngx.HTTP_UNLOCK,
		HTTP_PATCH = ngx.HTTP_PATCH,
		HTTP_TRACE = ngx.HTTP_TRACE,
	},
	
	logLevel = {
		STDERR = ngx.STDERR,
		EMERG = ngx.EMERG,
		ALERT = ngx.ALERT,
		CRIT = ngx.CRIT,
		ERR = ngx.ERR,
		WARN = ngx.WARN,
		NOTICE = ngx.NOTICE,
		INFO = ngx.INFO,
		DEBUG = ngx.DEBUG,
	},

	getConfigs = function()
		return configs
	end,
}

local loadables = { cookie = 1, orm = 1, request = 1, response = 1, router = 1, utils = 1, validator = 1 }
local application = {
	__index = function(self, key)
		local f = baseapi[key]
		if f then
			return f
		end
		
		f = loadables[key]
		if f == 1 then
			f = require(string.format('reeme.%s', key))
			if type(f) == 'function' then
				local r = f(self.__reeme)
				rawset(self.__reeme, key, r)
				loadables[key] = f
				return r
			end
			
		elseif f then
			local r = f(self.__reeme)
			rawset(self, key, r)
			return r
		end
	end,
}

local function lazyLoaderProc(self, key, ...)
	local lazyLoader = configs[key]
	local tp = type(lazyLoader)
	if tp == "table" then
		local fget = lazyLoader.get
		local ffree = lazyLoader.free
		if type(fget) == "function" then
			local r = fget(self, ...)
			if r and type(ffree) == "function" then
				rawget(self, "_lazyLoaders")[ffree] = r
			end
			return r
		end

	elseif tp == 'function' then
		return lazyLoader(self, ...)
	end
end

local preActionProc = nil
local appMeta = {
	__index = {
		init = function(self, cfgs)
			if not configs then
				--first in this LuaState
				
				if not cfgs then cfgs = { } end
				if not cfgs.dirs then cfgs.dirs = { } end
				cfgs.dirs.appRootDir = ngx.var.APP_ROOT
				if cfgs.devMode == nil then cfgs.devMode = true end
				if cfgs.viewFileExt == nil then cfgs.viewFileExt = '.html' end
				if not cfgs.dirs.appBaseDir then cfgs.dirs.appBaseDir = 'app' end
				if not cfgs.dirs.modelsDir then cfgs.dirs.modelsDir = 'models' end
				if not cfgs.dirs.viewsDir then cfgs.dirs.viewsDir = "views" end
				if not cfgs.dirs.controllersDir then cfgs.dirs.controllersDir = 'controllers' end
				
				configs = cfgs
			end
			
			return self
		end,
		
		preAction = function(self, func)
			if type(func) == 'function' then
				preActionProc = func
			end
			
			return self
		end,
		
		users = function(self, vals)
			local u = self.users
			for k,v in pairs(vals) do
				u[k] = v
			end
			return self
		end,
		
		--加载控制器，返回控制器实例和要执行的动作函数
		loadController = function(self, path, act)
			local dirs = configs.dirs
			local controlNew = require(string.format('%s.%s.%s', dirs.appBaseDir, dirs.controllersDir, string.gsub(path, '_', '.')))
			
			if type(controlNew) ~= 'function' then
				error(string.format('controller %s must return a function that has action functions', path))
			end
			
			local c = controlNew(act)
			local mth = c[act .. 'Action']
			local cm = getmetatable(c)			

			local metacopy = { __index = { __reeme = c } }
			setmetatable(metacopy.__index, application)

			if cm then
				if type(cm.__index) == 'function' then
					error(string.format("the __index of controller[%s]'s metatable must be a table", path))
				end
				
				cm.__call = lazyLoaderProc
				setmetatable(cm.__index, metacopy)
			else
				metacopy.__call = lazyLoaderProc
				setmetatable(c, metacopy)
			end

			rawset(c, "_lazyLoaders", { })
			
			return c, mth
		end,
		
		run = function(self)
			--require('mobdebug').start('192.168.3.13')
			local c
			local ok, err = pcall(function()
				local router = configs.router or require("reeme.router")
				local path, act = router(ngx.var.uri)
				local mth
				
				--载入控制器
				c, mth = self:loadController(path, act)
								
				local r
				if preActionProc then
					--执行动作前响应函数
					r = preActionProc(self, c, act, mth)
					local tp = type(r)

					if tp == 'table' then
						if r.response then
							mth = nil
							r = r.response
						elseif r.controller then
							c, mth = r.controller, r.method
						elseif r.method then
							mth = r.method
						end
					elseif tp == 'string' then
						mth = nil
						ngx.say(r)
					end
					
				elseif not mth then
					--如果没有动作前响应函数又没有动作，那么就报错
					error(string.format("the action %s of controller %s undefined", act, path))
				end

				--执行动作
				if mth then
					if self.users then
						for k,v in pairs(self.users) do
							rawset(c, k, v)
						end
						self.users = nil
					end
					
					r = mth(c)
				end
				if r then
					local tp = type(r)

					if tp == 'table' then
						ngx.say(getmetatable(r) and r:content() or c.utils.jsonEncode(r))
					elseif tp == 'string' then
						ngx.say(r)
					end
				end
				--require('mobdebug').done()
			end)

			if not ok then
				local msg = err.msg
				local msgtp = type(msg)
				if type(msg) == "string" then
					ngx.say(msg)
				elseif type(msg) == "table" then
					ngx.say(c.utils.jsonEncode(msg))
				elseif type(err) == "string" then
					ngx.say(err)
				end

				ngx.eof()
			end
			
			local lazyLoaders = rawget(c, "_lazyLoaders")
			for k, v in pairs(lazyLoaders) do
				k(c, v)
			end
			
			metacopy = nil
			c = nil
		end,
	}
}

return function()
	return setmetatable({ users = { } }, appMeta)
end