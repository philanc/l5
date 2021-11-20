
l5 = require "l5"

print("------------------------------------------------------------")
print("test_exec...")

-- test execve
--	env is exec'd with an environment containing only
--	"test_execve= ok" - so this is what it should print!
l5.execve("/usr/bin/env", {"/usr/bin/env"}, {"test_execve= ok."})


	

