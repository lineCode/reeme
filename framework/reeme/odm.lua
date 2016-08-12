local models = {}
local validTypes = { s = 1, i = 2, n = 3, b = 4 }
local modelmeta = require('reeme.odm.model')

local parseFields = function(m)
	local fields, plains = {}, {}
	
	for k,v in pairs(m.fields) do
		if type(k) == 'string' then
			local first = v:byte()
			local isai, allownull = false, false
			
			if first == 35 then --#
				v = v:sub(2)
				allownull = true
			elseif first == 42 then --*
				v = v:sub(2)
				isai = true
			end
			
			local maxl = v:match('((%d+))')
			if maxl then
				local t = v:sub(1, 1)
				if not validTypes[t] then
					return false
				end
				
				local defv = v:find(')')
				if defv and #v > defv then
					defv = v:sub(defv + 1)
				else
					defv = nil
				end

				fields[k] = { maxlen = tonumber(maxl), ai = isai, null = allownull, type = t, default = defv }
				plains[#plains + 1] = k
			else
				return false
			end
		end
	end
	
	if #plains > 0 then
		m.__fields = fields
		m.__fieldPlain = 'A.' .. table.concat(plains, ',A.')
		return true
	end
	
	return false
end

local ODM = {
	__index = {
		--使用一个定义的模型
		--不能使用require直接引用一个模型定义的Lua文件来进行使用，必须通过本函数来引用
		use = function(self, name)
			local m = models[name]
			local reeme = self.R
			
			if not m then			
				local cfgs = reeme:getConfigs()
				
				m = require(string.format('%s.%s.%s', cfgs.dirs.appBaseDir, cfgs.dirs.modelsDir, name))
				if type(m) ~= 'table' or type(m.fields) ~= 'table' then
					error(string.format("use('%s') get a invalid model declaration", name))
					return nil
				end
				
				local oldm = getmetatable(m)
				if oldm and type(oldm.__index) ~= 'table' then
					error(string.format("use('%s') get a model table, but the __index of its metatable not a table", name))
					return nil
				end
				
				m.__name = name
				m.__oldm = oldm
				if not parseFields(m) then
					error(string.format("use('%s') parse failed: may be no valid field or field(s) declaration error", name))
					return nil
				end

				setmetatable(oldm and oldm.__index or m, modelmeta)
				models[name] = m
			end
			
			m.__reeme = reeme
			return m
		end,
		
		--清理所有的model缓存
		clear = function(self)
			for k,m in pairs(models) do
				if m.__oldm then
					setmetatable(m, m.__oldm)
				end
				
				m.__name, m.__fields, m.__fieldPlain, m.__oldm = nil, nil, nil, nil
			end
			
			models = {}
		end,
		
		--重新加载指定的Model
		reload = function(self, name)
			if models[name] then
				models[name] = nil
				return self:use(name)
			end		
		end,
	}
}

return function(reeme)
	local odm = { R = reeme }
	
	setmetatable(odm, ODM)
	rawset(reeme, 'odm', odm)

	return odm
end