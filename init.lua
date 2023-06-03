local path = minetest.get_modpath(minetest.get_current_modname())
local template_engine = dofile(path .. "/template_engine4.lua")

local known_keys = {"drop", "RMB", "LMB", "up", "down", "left", "right", "jump",
	"sneak", "aux1"}
local known_keys_str = table.concat(known_keys, ", ")
for i = 1,#known_keys do
	known_keys[known_keys[i]] = true
	known_keys[i] = nil
end

-- needs to be helpful
local default_cmdlist =
	"LMB\n" ..
	"/help cwct\n" ..
	"/cwct\n" ..
	"\n" ..
	"RMB right left\n" ..
	"/me pressed right mouse button, right and left at once\n" ..
	"\n" ..
	"RMB right !left\n" ..
	"/me pressed right mouse button, right, but not left at once\n" ..
	"\n" ..
	"# The tool works when it is dropped, placed (RMB) or used (LMB).\n" ..
	"# Supported keys and buttons:\n" ..
	"# " .. known_keys_str .. "\n"


-- returns the metadata of the tool or the default list
local function get_metadata(itemstack, player)
	if not player
	or not itemstack then
		return default_cmdlist
	end

	local metadata = itemstack:get_meta():get_string"commands"
	if not metadata
	or metadata == "" then
		return default_cmdlist
	end

	return metadata
end

-- Parse code for the "simple" case to execute commands conditioned on pressed
-- keys
local function get_commands_simple(source, pcontrol)
	local keys_pressed = false
	local commands = {}
	local lines = source:split"\n"
	for li = 1, #lines do
		local line = lines[li]:trim()
		local first_char = line:sub(1, 1)
		if first_char == "/" then
			-- chatcommand
			if keys_pressed then
				commands[#commands+1] = line
			end
		elseif first_char ~= "" and first_char ~= "#" then
			-- keys requirement
			keys_pressed = true
			local required_keys = line:split" "
			for ki = 1, #required_keys do
				local key = required_keys[ki]
				if key:sub(1, 1) == "!" then
					key = key:sub(2)
					if not known_keys[key] then
						return false, "Unknown key: \"" .. key ..
							"\", available keys: " .. known_keys_str
					end
					if pcontrol[key] then
						keys_pressed = false
						break
					end
				elseif not known_keys[key] then
					return false, "Unknown key: \"" .. key ..
						"\", available keys: " .. known_keys_str
				elseif not pcontrol[key] then
					keys_pressed = false
					break
				end
			end
		end
		-- else it's a comment or empty line, ignore
	end
	return commands
end

-- Get a list of to-be-executed chat commands from the user-provided string
local function get_commands(source, pname, controls)
	local source_type = "simple"
	if source:sub(1,2) == "#!" then
		local lb = source:find("\n")
		if not lb then
			return false, "Missing \n after the first line"
		end
		local bang = source:sub(3, lb - 1):trim()
		source_type = bang:match("%S+") or ""
		source = source:sub(lb + 1)
	end
	if source_type == "simple" then
		return get_commands_simple(source, controls)
	end
	if source_type == "lua_template" then
		if not minetest.get_player_privs(pname).server then
			return false, "server privilege is required for Lua templating"
		end
		local lines, err = template_engine.compile(source, {control = controls})
		if not lines then
			return false, err
		end
		local commands = {}
		lines = lines:split("\n")
		for i = 1, #lines do
			local cmd = lines[i]:trim()
			if cmd:sub(1, 1) == "/" then
				commands[#commands+1] = cmd
			elseif cmd ~= "" then
				return false, 'Found a non-chatcommand line: "' .. cmd .. '"'
			end
		end
		return commands
	end
	return false, 'Invalid code type: "' .. source_type ..
		'". Supported are "lua_template" and "simple" (default).'
end

-- runs the chatcommands of the tool
local function run_commands(source, player, force_controls)
	if type(source) ~= "string" then
		-- the itemstack was given
		source = get_metadata(source, player)
	end
	local pcontrol = player:get_player_control()
	for i = 1,#force_controls do
		pcontrol[force_controls[i]] = true
	end
	local pname = player:get_player_name()
	local commands, err = get_commands(source, pname, pcontrol)
	if not commands then
		minetest.chat_send_player(pname, "Chatcommand execution has failed: " ..
			err)
		return
	end

	-- abort if no command is to be executed
	if not commands[1] then
		minetest.chat_send_player(pname, "No chatcommands executed.")
		return
	end

	for ci = 1, #commands do
		local cmd = commands[ci]
		for mi = 1, #minetest.registered_on_chat_messages do
			minetest.registered_on_chat_messages[mi](pname, cmd)
		end
	end

	minetest.log("info",
		"[command_tool] " .. pname .. " used the command tool.")
	minetest.chat_send_player(pname, "Chatcommands executed.")
end

-- adds the item
minetest.register_craftitem("command_tool:tool", {
	description = "command tool\rconfigure with /cwct",
	inventory_image = "command_tool.png",
	range = 0,
	stack_max = 1,
	on_secondary_use = function(itemstack, player)
		run_commands(itemstack, player, {"RMB"})
	end,
	on_use = function(itemstack, player)
		run_commands(itemstack, player, {"LMB"})
	end,
	on_drop = function(itemstack, player)
		run_commands(itemstack, player, {"drop"})
	end,
})

-- shows the configuration formspec
local function configure_command_tool(pname, player)
	local item = player:get_wielded_item()
	if item:get_name() ~= "command_tool:tool" then
		minetest.chat_send_player(pname,
			"You need to wear the command tool to configure it…")
		return
	end
	local metadata = get_metadata(item, player)
	minetest.show_formspec(pname, "command_tool:formspec",
		"formspec_version[3]" ..
		"size[10,10]" ..
		"textarea[0.3,0.3;9.4,8.1;text;;" ..
			minetest.formspec_escape(metadata) .. "]" ..
		"button[0.3,8.7;9.4,1.0;;Save configuration]"
	)
end

-- sets the new configuration to the tool
local function set_config(player, text)
	if not player
	or not text
	or text == "" then
		return
	end
	local pname = player:get_player_name()
	local item = player:get_wielded_item()
	if item:get_name() ~= "command_tool:tool" then
		minetest.chat_send_player(pname, "Something went wrong.")
		return
	end
	item:get_meta():set_string("commands", text)
	player:set_wielded_item(item)
	minetest.chat_send_player(pname, "configured wielded command tool")
	return true
end

-- when the player exits the config formspec
minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "command_tool:formspec" then
		return
	end
	local pname = player:get_player_name()
	local text = fields.text
	if not text
	or text == "" then
		return
	end
	minetest.after(0.1, function()
		set_config(minetest.get_player_by_name(pname), text)
	end)
end)

-- adds the configuration chatcommand
minetest.register_chatcommand("cwct", {
	params = "[newdata]",
	description = "configure wielded command tool",
	privs = {interact = true},
	func = function(name, param)
		local player = minetest.get_player_by_name(name)
		if not player then
			return false, "Player not found"
		end
		if param
		and param ~= "" then
			set_config(player, param)
			return
		end
		configure_command_tool(name, player)
	end,
})
