local models = {}
local modelmeta = require('reeme.orm.model')
local builder = require('reeme.orm.mysqlbuilder')
local parseFields = require('reeme.orm.common').parseFields

local mysql = {
	__index = {
		defdb = function(self, db)
			local old = self._defdb
			if db then
				self._defdb = db
			end
			return old
		end,
		
		--使用一个定义的模型
		--不能使用require直接引用一个模型定义的Lua文件来进行使用，必须通过本函数来引用
		--可以使用.号表示多级目录，名称的最后使用@符号可以表示真实的表名，这样可以同模型多表，比如: msgs@msgs_1
		use = function(self, srcname, db)
			--将真实表名和模型名分离
			local name, truename = string.cut(srcname, '@')
			--库名和表名分离
			local dbname, tbname = string.cut(name, '.')
			
			if not tbname then
				--表名不存在说明没有.号在里面，那么交换两个名字
				dbname, tbname = nil, dbname
			end

			--优先使用参数给定的库/库名，如果不存在就判断是否模型名称指定了库名，如果未指定或库不存在，那么就使用默认的db
			local reeme = self.R
			if db then
				if type(db) == 'string' then
					db = reeme(db)
				end
				
				if not db then
					if dbname then
						db = reeme(dbname) or self._defdb
					else
						db = self._defdb
					end
				end
				
			elseif dbname then
				db = reeme(dbname) or self._defdb
			else
				db = self._defdb
			end

			--然后去缓存中寻找已经产生过的
			local cacheId = name .. tostring(db)
			local m = self.caches[cacheId]
			
			if m then
				return m
			end
			
			--没有缓存，那么获取模型			
			local idxName = string.format('%s-%s', ngx.var.APP_NAME or ngx.var.APP_ROOT, name)
			
			m = models[idxName]
			if not m then
				--模型还未存在，现在就加载
				local cfgs = reeme:getConfigs()
				local modelsDir = cfgs.dirs.modelsDir

				if modelsDir:byte(1) == 47 then
					m = require(string.format('%s.%s', modelsDir, name))
				else
					m = require(string.format('%s.%s.%s', cfgs.dirs.appBaseDir, modelsDir, name))
				end
				
				if type(m) ~= 'table' or type(m.fields) ~= 'table' then
					error(string.format("mysql:use('%s') get a invalid model declaration", name))
					return nil
				end			

				local err = parseFields(m, name)
				if err ~= true then
					error(string.format("mysql:use('%s') parse failed: %s", name, err))
					return nil
				end

				models[idxName] = m
			end

			--产生新的缓存
			r = setmetatable({
				__reeme = reeme,
				__builder = builder,
				__name = truename or tbname,
				__fields = m.__fields,
				__fieldsPlain = m.__fieldsPlain,
				__fieldIndices = m.__fieldIndices,
				__db = db
			}, modelmeta)

			self.caches[cacheId] = r
			return r
		end,
		
		--使用多个，并以table返回所有被使用的
		uses = function(self, names, db)
			local tp = type(names)
			
			if type(db) == 'string' then
				db = reeme(db)
			end
			
			if tp == 'table' then
				local r = table.new(0, #names)
				for i = 1, #names do
					local n = names[i]
					r[n] = self:use(n, db)
				end
				return r
				
			elseif tp == 'string' then
				local r = table.new(0, 10)
				string.split(names, ',', string.SPLIT_ASKEY, r)

				for k,v in pairs(r) do
					r[k] = self:use(k, db)
				end
				return r
			end
		end,
		
		--事务
		begin = function(self, db)
			if type(db) == 'string' then
				db = self.R(db)
				if not db then
					return self
				end
			elseif not db then
				db = self._defdb
			end
			
			if db and not self.transaction[db] then
				self.transaction[db] = 1
				self.transcount = self.transcount + 1
				
				db:query('SET AUTOCOMMIT=0')
				db:query('BEGIN')
			end
			
			return self
		end,
		commit = function(self, db)
			if db then
				db:query('COMMIT')
				self.transaction[db] = nil
			elseif self.transcount > 0 then
				for v,_ in pairs(self.transaction) do
					v:query('COMMIT')
				end
				self.transaction = {}
				self.transcount = 0
			end
			
			return self
		end,
		rollback = function(self, db)
			if db then
				db:query('ROLLBACK')
				self.transaction[db] = nil
			elseif self.transcount > 0 then
				for v,_ in pairs(self.transaction) do
					v:query('ROLLBACK')
				end
				self.transaction = {}
				self.transcount = 0
			end
			
			return self
		end,

		--使用回调的方式执行事务，当事务函数返回true时就会提交，否则就会回滚
		autocommit = function(self, func, ...)
			if func then
				local dbs = { ... }
				for i = 1, #dbs do
					local db = dbs[i]
					
					db:query('SET AUTOCOMMIT=0')
					db:query('BEGIN')
					if func() == true then
						db:query('COMMIT')
						return true
					else
						db:query('ROLLBACK')
					end
				end
			end

			return false
		end,
		
		--退出的时候清理所有，未提交的事务将被rollback
		clearAll = function()
			if self.transcount > 0 then
				for v,_ in pairs(self.transaction) do
					v:query('ROLLBACK')
				end
				self.transcount = 0
			end

			self.caches = nil
			self.transaction = nil
		end
	},
	
	__call = function(self, p1, p2)
		return self:use(p1, p2)
	end
}

return function(reeme)
	return setmetatable({ R = reeme, transaction = {}, transcount = 0, caches = {} }, mysql)
end