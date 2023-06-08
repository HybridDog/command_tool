# Usage

The chat command tool can be configured with the `/cwct` command.

## Simple mode

In this mode, each line is either empty, a chatcommand, or a list of required
key/button presses.
If a list of keys/buttons is specified, the following lines of chat commands
are executed until the next list.

Key/button conditions:
* Pressed: The name of the key/button is present in the list
* Not pressed: A `!` followed by the name of the key/button is present in the
  list
* Any: The name of the key/button is absent from the list; the key/button is not
  used to determine if the following commands should be executed

For examples, see the default configuration of a new chat command tool.


## Lua templating mode

If the first line is `#!lua_template`, the remaining lines are processed as a
Lua template.
The template engine is explained at https://nachtimwald.com/2022/08/28/lua-template-engine-yet-again/.
Escaping (`{= mode =}`) is not supported in this mod, and the Lua code is
executed with [safer_lua](https://github.com/joe7575/safer_lua) unless the user
has server privilege.

```
#!lua_template
{% if S.control.LMB then %}
/me has pressed the left mouse button
{% end %}
```

# TODO
* Describe this mod better in the Readme or link to a forum topic
* Limit the number of commands for safety
* Change the texture
* Add position variables for the lua template case
* safer_lua does not prevent memory exhaustion with very long strings:
  ```
  /lua function err_clbk(_, error_msg) err = error_msg minetest.chat_send_all(err) end
  /lua err = nil code = safer_lua.init(nil, "", 'm="mm" m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m m=m..m  f=m.."f" m=m..m..m f=f..f g=f.."g" h=f.."h"', {log=print}, err_clbk) assert(not err) safer_lua.run_loop(nil, 0, code, err_clbk)
  ```
  -> Disable lua templating by default even with safer_lua, and add a setting to enable it explicitly
