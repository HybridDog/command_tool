local load_time_start = os.clock()

--[[	look of the meta
left aux1
/me ha
/me not here
sneak aux1
/help
]]

local function run_commands(metadata, player, force_controls)
	local pcontrol = player:get_player_control()
	for _,i in pairs(force_controls) do
		pcontrol[i] = true
	end
	local keys_pressed = false
	local commands = {}
	for _,i in ipairs(string.split(metadata, "\n")) do
		if i ~= "" then
			if string.sub(i, 1, 1) == "/" then
				if keys_pressed then
					table.insert(commands, i)
				end
			else
				keys_pressed = true
				local current_keys = string.split(i, " ")
				for _,i in pairs(current_keys) do
					if not pcontrol[i] then
						keys_pressed = false
						break
					end
				end
			end
		end
	end

	local pname = player:get_player_name()

	-- abort if no command is found
	if not commands[1] then
		minetest.chat_send_player(pname, "No chatcommands executed.")
		return
	end

	for _,cmd in ipairs(commands) do
		for _,func in pairs(minetest.registered_on_chat_messages) do
			func(pname, cmd)
		end
	end

	minetest.log("info", "[command_tool] "..pname.." used the command tool.")
	minetest.chat_send_player(pname, "Chatcommands executed.")
end

local function get_metadata(itemstack, player)
	if not player
	or not itemstack then
		return
	end

	local item = itemstack:to_table()
	local metadata = item.metadata
	if not metadata
	or metadata == "" then
		return
	end

	return metadata
end

minetest.register_craftitem("command_tool:tool", {
	description = "command tool",
	inventory_image = "command_tool.png",
	--range = 0,
	stack_max = 1,
	on_place = function(itemstack, player)
		local metadata = get_metadata(itemstack, player)
		if metadata then
			run_commands(metadata, player, {"RMB"})
		end
	end,
	on_use = function(itemstack, player)
		local metadata = get_metadata(itemstack, player)
		if metadata then
			run_commands(metadata, player, {"LMB"})
		end
	end,
	on_drop = function(itemstack, player)
		local metadata = get_metadata(itemstack, player)
		if metadata then
			run_commands(metadata, player, {"drop"})
		end
	end,
})

-- needs to be helpful
local default_cmdlist =
	"jump\n"..
	"right left RMB\n"..
	"/me tests\n"..
	"/me still tests\n"..
	"LMB\n"..
	"/help cwct\n"..
	"sneak\n"..
	"aux1\n"..
	"down\n"..
	"up\n"

local function configure_command_tool(pname, player)
	local item = player:get_wielded_item()
	if item:get_name() ~= "command_tool:tool" then
		minetest.chat_send_player(pname, "You need to wear the command tool to configure it…")
		return
	end
	local metadata = get_metadata(item, player) or default_cmdlist
	minetest.show_formspec(pname, "command_tool:formspec",
		"size[5,6]"..
		"textarea[0.3,0;5,6;text;;"..minetest.formspec_escape(metadata).."]"..
		"button[0.3,5;2,2;save;save]"..
		"button[2.6,5;2,2;help;help]"
	)
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "command_tool:formspec" then
		return
	end
	local pname = player:get_player_name()
	if not fields.save then
		return
	end
	local text = fields.text
	if not text then
		minetest.chat_send_player(pname, "No text?")
		return
	end
	minetest.after(0, function()
		local player = minetest.get_player_by_name(pname)
		if not player then
			return
		end
		local item = player:get_wielded_item()
		if item:get_name() ~= "command_tool:tool" then
			minetest.chat_send_player(pname, "Something went wrong.")
			return
		end
		item:set_metadata(text)
		player:set_wielded_item(item)
		minetest.chat_send_player(pname, "configured wielded command tool")
	end)
end)

minetest.register_chatcommand("cwct", {
	params = "",
	description = "configure wielded command tool",
	privs = {interact = true},
	func = function(pname)
		local player = minetest.get_player_by_name(pname)
		if not player then
			return false, "Player not found"
		end
		configure_command_tool(pname, player)
	end,
})


local time = math.floor(tonumber(os.clock()-load_time_start)*100+0.5)/100
local msg = "[command_tool] loaded after ca. "..time
if time > 0.05 then
	print(msg)
else
	minetest.log("info", msg)
end
