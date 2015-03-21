local load_time_start = os.clock()

--[[	look of the meta
left aux1
/me ha
/me not here
sneak aux1
/help
]]

local function run_commands(metadata, player)
	local pcontrol = player:get_player_control()
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
	local metadata = item["metadata"]
	if not metadata
	or metadata == "" then
		return
	end

	return metadata
end

minetest.register_craftitem("command_tool:tool", {
	description = "command tool",
	inventory_image = "command_tool.png",
	range = 0,
	stack_max = 1,
	on_place = function(itemstack, player)
		local metadata = get_metadata(itemstack, player)
		if metadata then
			run_commands(metadata, player)
		end
	end,
})

local function configure_command_tool(pname, player)
	local item = player:get_wielded_item()
	if item:to_string() ~= "command_tool:tool" then
		minetest.chat_send_player(pname, "You need to wear the command tool to configure it…")
	end
	local metadata = get_metadata(item, player)
	minetest.chat_send_player(pname, metadata)
	return true, "configured wielded command tool"
end

minetest.register_chatcommand("configure_command_tool", {
	params = "",
	description = "configure wielded command tool",
	privs = {interact = true},
	func = function(pname)
		local player = minetest.get_player_by_name(pname)
		if not player then
			return false, "Player not found"
		end
		return configure_command_tool(pname, player)
	end,
})


local time = math.floor(tonumber(os.clock()-load_time_start)*100+0.5)/100
local msg = "[command_tool] loaded after ca. "..time
if time > 0.05 then
	print(msg)
else
	minetest.log("info", msg)
end
