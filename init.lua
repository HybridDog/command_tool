local known_keys = {"drop", "RMB", "LMB", "up", "down", "left", "right", "jump",
	"sneak", "aux1"}
local known_keys_str = table.concat(known_keys, ", ")
for i = 1,#known_keys do
	known_keys[known_keys[i]] = true
	known_keys[i] = nil
end

-- needs to be helpful
local default_cmdlist =
	"RMB right left\n" ..
	"/me tests the command tool\n" ..
	"/me pressed right mouse button, right and left at once\n" ..
	"RMB right !left\n" ..
	"/me pressed right mouse button, right, but not left at once\n" ..
	"LMB\n" ..
	"/help cwct\n" ..
	"drop sneak aux1 down up jump\n" ..
	"/me pressed a lot keys at once\n" ..
	"# Currently the tool works on dropping, placing and using\n" ..
	"# " .. known_keys_str .. "\n"

-- used when the player used an unknown key
local function handle_invalid_key(pname, key)
	if not known_keys[key] then
		minetest.chat_send_player(pname, "Unknown key: \"" .. key ..
			"\", available keys: " .. known_keys_str)
		return true
	end
end

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

-- runs the chatcommands of the tool
local function run_commands(metadata, player, force_controls)
	if type(metadata) ~= "string" then
		-- the itemstack was given
		metadata = get_metadata(metadata, player)
	end
	local pcontrol = player:get_player_control()
	for i = 1,#force_controls do
		pcontrol[force_controls[i]] = true
	end
	local keys_pressed = false
	local commands = {}
	local lines = metadata:split"\n"
	for i = 1,#lines do
		local line = lines[i]
		local first_char = line:sub(1, 1)
		if first_char == ""
		or first_char == "#" then
			-- comment or empty line, ignore
		elseif first_char == "/" then
			-- chatcommand
			if keys_pressed then
				commands[#commands+1] = line
			end
		else
			-- keys requirement
			keys_pressed = true
			local required_keys = line:split" "
			for i = 1,#required_keys do
				local key = required_keys[i]
				if key:sub(1, 1) == "!" then
					key = key:sub(2)
					if handle_invalid_key(pname, key) then
						return
					end
					if pcontrol[key] then
						keys_pressed = false
						break
					end
				elseif handle_invalid_key(pname, key) then
					return
				elseif not pcontrol[key] then
					keys_pressed = false
					break
				end
			end
		end
	end

	local pname = player:get_player_name()

	-- abort if no command is to be executed
	if not commands[1] then
		minetest.chat_send_player(pname, "No chatcommands executed.")
		return
	end

	for i = 1,#commands do
		local cmd = commands[i]
		for i = 1,#minetest.registered_on_chat_messages do
			minetest.registered_on_chat_messages[i](pname, cmd)
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
	--range = 0,
	stack_max = 1,
	on_place = function(itemstack, player)
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
		"size[10,10]"..
		"textarea[0.3,0;10,10.5;text;;" ..
		minetest.formspec_escape(metadata) .. "]" ..
		"button[0,9;10,2;;     Save\rconfiguration]"
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
	minetest.after(0.1, function(pname)
		set_config(minetest.get_player_by_name(pname), text)
	end, pname)
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
