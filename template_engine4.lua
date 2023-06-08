--- Template Engine.
--
-- Takes a string with embedded Lua code block and renders
-- it based on the content of the blocks.
--
-- All template blocks start with '{ + start modifier' and
-- end with 'end modifier + }'.
--
-- Supports:
--  * {# text #}	   for comments.
--  * {% expression %} for running Lua code.
--  * {{ var }}		for printing.
--
-- Template block ends that end a line (whether they are part of a valid
-- block or not) will not create a new line. Use a space ' ' at the end
-- of the line if you want a new line preserved. The space will be removed.
-- So use two if you want the newline and the space preserved.
--
-- Multi-line strings in Lua blocks are supported but
-- [[ is not allowed. Use [=[ or some other variation.
--
-- Internal variables and functions that are run in the same environment
-- as the template are prefixed with an underscore '_'. Any functions
-- functions or variables created in the template should not use this prefix.
--
-- The template will be run in a sand box with a set of safe globals configured.
-- The sand box can be extended by proving an env with additional globals that
-- should be available. Globals can be added but not removed. Additionally the
-- env should contain any variables that the template will need to access such
-- as setting a username for display in the template.
--
-- New lines are normalized to \n. If \r\n new lines are required a
-- replacement will need to take place after the engine runs on the template.

local M = {}

-- Note: Modifiers and end modifiers must be symbols.

--- Map of start block modifiers to their end block modifier.
local END_MODIFIER = {
	["#"] = "#",
	["%"] = "%",
	["{"] = "}",
}

--- Actions that should be taken when a block is encountered.
local MODIFIER_FUNC = {
	["#"] = function()
		return ""
	end,

	["%"] = function(code)
		return code
	end,

	["{"] = function(code)
		return ("_ret.add(%s)"):format(code)
	end,
}

--- Handle newline rules for blocks that end a line.
-- Blocks ending with a space keep their newline and blocks that
-- do not lose their newline.
local function handle_block_ends(text)
	local modifier_set = ""

	-- Build up the set of end modifiers.
	-- Prefix each modifier with % to ensure they are escaped properly for gsub.
	-- Block ends are and must always be symbols.
	for _,v in pairs(END_MODIFIER) do
		modifier_set = modifier_set.."%"..v
	end

	text = text:gsub("(["..modifier_set.."])} \n", "%1}\n\n")
	text = text:gsub("(["..modifier_set.."])}\n", "%1}")

	return text
end

--- Append text or code to the builder.
local function appender(builder, text, code)
	if code then
		builder[#builder+1] = code
	elseif text then
		-- [[ has a \n immediately after it. Lua will strip
		-- the first \n so we add one knowing it will be
		-- removed to ensure that if text starts with a \n
		-- it won't be lost.
		builder[#builder+1] = "_ret.add([[\n".. text .."]])"
	end
end

--- Takes a string and determines what kind of block it
-- is and takes the appropriate action.
--
-- The text should be something like:
-- "{{ ... }}"
--
-- If the block is supported the begin and end tags will
-- be stripped and the associated action will be taken.
-- If the tag isn't supported the block will be output
-- as is.
local function run_block(builder, text)
	local func
	local modifier

	 -- Text is {...
	 -- Pull out the character after { to determine if we
	 -- have a modifier and what action needs to be taken.
	modifier = text:sub(2, 2)

	func = MODIFIER_FUNC[modifier]
	if func then
		appender(builder, nil, func(text:sub(3, #text-3)))
	else
		appender(builder, text)
	end
end

--- Compile a Lua template into a string.
--
-- @param	  tmpl The template.
-- @param[opt] env  Environment table to use for sandboxing.
--    This table will be modified.
-- @param[opt] use_safer_lua  If true, sandbox with the safer_lua Minetest mod
--
-- return Compiled template.
function M.compile(tmpl, env, use_safer_lua)
	-- Turn the template into a string that can be run though
	-- Lua. Builder will be used to efficiently build the string
	-- we'll run. The string will use it's own builder (_ret). Each
	-- part that comprises _ret will be the various pieces of the
	-- template. Strings, variables that should be printed and
	-- functions that should be run.
	local builder = {
		"_ret = Array()",
	}
	local pos	 = 1
	local b
	local modifier
	local func
	local err
	local ret
	local out

	if tmpl == nil or #tmpl == 0 then
		return ""
	end

	-- Normalize new lines
	tmpl = tmpl:gsub("\r\n", "\n")

	env = env or {}
	-- Add a function to pass the generated output
	env._pass_result = function(x) out = x end
	if not use_safer_lua then
		-- Add some globals to the env that restricts what the template can do.
		env["ipairs"]   = ipairs
		env["next"]	 = next
		env["pairs"]	= pairs
		env["pcall"]	= pcall
		env["tonumber"] = tonumber
		env["tostring"] = tostring
		env["type"]	 = type
		env["utf8"]	 = utf8
		env["math"]	 = math
		env["string"]   = string
		env["table"]	= {
			concat = table.concat,
			insert = table.insert,
			move   = table.move,
			remove = table.remove,
			sort   = table.sort,
		}
		env["os"]	   = {
			clock	= os.clock,
			date	 = os.date,
			difftime = os.difftime,
			time	 = os.time,
		}
		-- Partly-implemented replacements for safer_lua functionality
		env.S = env
		env["Array"] = function(...)
			local Data = {...}
			return {
				add = function(x)
					Data[#Data+1] = x
				end,
				__dump = function()
					return {Data = Data}
				end
			}
		end
	end

	-- Handle the new line rules for block ends.
	tmpl = handle_block_ends(tmpl)

	while pos < #tmpl do
		-- Look for start of a block.
		b = tmpl:find("{", pos)
		if not b then
			break
		end

		-- Check if this is a block or escaped { or not followed by block modifier.
		-- We store the next character as the modifier to help us determine if
		-- we have encountered a block or not.
		modifier = tmpl:sub(b+1, b+1)
		if tmpl:sub(b-1, b-1) == "\\" then
			appender(builder, tmpl:sub(pos, b-2))
			appender(builder, "{")
			pos = b+1
		elseif not END_MODIFIER[modifier] then
			appender(builder, tmpl:sub(pos, b+1))
			pos = b+2
		else
			-- Some modifiers for block ends aren't the same as the block start modifier.
			modifier = END_MODIFIER[modifier]
			-- Add all text up until this block.
			appender(builder, tmpl:sub(pos, b-1))
			-- Find the end of the block.
			if modifier == "%" then
				pos = tmpl:find("[^\\]?%%}", b)
			else
				pos = tmpl:find(("[^\\]?%s}"):format(modifier), b)
			end
			if pos then
				-- If we captured a character before the modifier move past it.
				if tmpl:sub(pos, pos) ~= modifier then
					pos = pos+1
				end
				run_block(builder, tmpl:sub(b, pos+2))
				-- Skip past the *} (pos points to the start of *}).
				pos = pos+2
			else
				-- Add back the { because we don't have an end block.
				-- We want to keep any text that isn't in a real block.
				appender(builder, "{")
				pos = b+1
			end
		end
	end
	-- Add any text after the last block. Or all of it if there
	-- are no blocks.
	if pos then
		appender(builder, tmpl:sub(pos, #tmpl))
	end

	-- Create the compiled template.
	builder[#builder+1] = "S._pass_result(_ret)"

	local lua_source = table.concat(builder, "\n")
	if use_safer_lua then
		local function err_clbk(_, error_msg)
			err = error_msg
		end
		local code = safer_lua.init(nil, "", lua_source, env, err_clbk)
		if err then
			return nil, err
		end
		safer_lua.run_loop(nil, 0, code, err_clbk)
	else
		-- Run the Lua code we built though Lua and get the result.
		-- Use luadstring instead of load for Lua 5.1 compatibility
		func, err = loadstring(lua_source)
		if not func then
			return nil, err
		end
		setfenv(func, env)
		ret, err = pcall(func)
		if not ret then
			return nil, err
		end
	end
	if not out then
		return nil, err
	end
	return table.concat(out.__dump().Data, "\n")
end

--- Compile a Lua template into a string by
-- reading the template from a file.
--
-- @param	  name The file name to read from.
-- @param[opt] env  Environment table to use for sandboxing.
--
-- return Compiled template.
function M.compile_file(name, env)
	local f, err = io.open(name, "rb")
	if not f then
		return err
	end
	local t = f:read("*all")
	f:close()
	return M.compile(t, env)
end

return M

