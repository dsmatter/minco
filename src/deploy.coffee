fs      = require "fs"
path    = require "path"
clc     = require "cli-color"
{spawn} = require "child_process"

script_path = "/tmp/deploy.bash"

# Read config file
# FIXME: modulize
config_str = fs.readFileSync "deploy.json", "UTF-8"
config = JSON.parse config_str

# Open connection to server
p = spawn "ssh", [config["server"], "bash -s"], stdio: ["pipe", 1, 2]

# Write script directly to SSH's STDIN
script = p.stdin

# script.end()
# script = fs.createWriteStream "/tmp/deploy.bash"

# Define script writing facilities
queue_echo = (text) ->
  script.write 'echo "' + text + '"\n'

queue_log = (desc, cf=clc.white.bold) ->
  queue_echo (cf "----> " + desc)

queue_log_cmd = (cmd...) ->
  queue_log (cmd.join " "), clc.white

queue_if = (cond, then_queuer, else_queuer) ->
  script.write "if #{cond}; then\n"
  then_queuer()
  if else_queuer?
    script.write "else\n"
    else_queuer()
  script.write "fi\n"

queue_function = (name, body_queuer) ->
  script.write "function " + name + " {\n"
  body_queuer()
  script.write "}\n"

queue_error_check = ->
  queue_if "[[ $? -ne 0 ]]",
    (->
      queue_log "Command failed with code $?", clc.red
      queue_raw "cleanup; exit 1"),
    (->
      queue_log "ok", clc.green)

queue_cmd = (cmd, args...) ->
  # Log command - don't show ugly quotes
  queue_log_cmd cmd, args...

  # Run command
  quoted_args = (args.map (arg) -> '"' + arg + '"').join " "
  script.write cmd + " " + quoted_args + "\n"

  # Write error check
  queue_error_check()

queue_cd = (dir) ->
  queue_cmd "cd", dir

queue_raw = (raw) ->
  script.write raw + "\n"

queue_raw_cmd = (cmd) ->
  queue_log_cmd cmd
  queue_raw cmd
  queue_error_check()

####
### Send commands to server ###
####

### Write cleanup function ###
queue_function "cleanup", ->
  release_dir = path.join dir, "releases", "$rno"
  queue_if "[[ ! -z $rno ]]", ->
    queue_cmd "rm", "-rf", release_dir

### Basic setup ###
queue_log "Create subdirs"

dir = config["server_dir"]
for subdir in ["shared", "releases", "tmp"]
  queue_cmd "mkdir", "-p", (path.join dir, subdir)

# Create shared dirs
queue_log "Create shared dirs"

for shared_dir in config["shared_dirs"]
  queue_cmd "mkdir", "-p", (path.join dir, "shared", shared_dir)

### Fetch code ###
queue_log "Fetch code"

# Checkout repo
queue_if "[[ ! -d scm/.git ]]", ->
  queue_cd (path.join dir, "tmp")
  queue_cmd "rm", "-rf", "scm"
  queue_cmd "git", "clone", "-b", config["branch"], config["repo"], "scm"

# Update repo
queue_cd (path.join dir, "tmp", "scm")
queue_cmd "git", "checkout", config["branch"]
queue_cmd "git", "pull"

# Copy code to release dir
queue_log "Copy code to release dir"

queue_raw 'rno="$(readlink "' + (path.join dir, "current") + '")"'
queue_raw 'rno="$(basename "$rno")"'
queue_raw "(( rno = rno + 1 ))"
queue_cmd "cp", "-r", (path.join dir, "tmp", "scm"), (path.join dir, "releases", "$rno")

### Link shared dirs ###
queue_log "Link shared dirs"

queue_cd (path.join dir, "releases", "$rno")
for shared_dir in config["shared_dirs"]
  queue_cmd "mkdir", "-p", (path.dirname shared_dir)
  queue_cmd "ln", "-s", (path.join dir, "shared", shared_dir), shared_dir

### Run pre-start scripts ###
queue_log "Run pre-start scripts"
for cmd in config["prerun"]
  queue_raw_cmd cmd

### Start the service ###
queue_log "Start service"
queue_raw_cmd config["run_cmd"]

### Update current link ###
queue_log "Update current link"

queue_cd (path.join dir)
queue_if "[[ -h current ]]", ->
  queue_cmd "rm", "current"
queue_cmd "ln", "-s", "releases/$rno", "current"

### Clean the release dir ###
queue_log "Cleaning release dir"

queue_cd (path.join dir, "releases")
queue_raw 'release_dirs="$(find . -maxdepth 1 -mindepth 1 -type d -printf "%f\\n" | sort -n)"'
queue_raw 'num_dirs="$(echo "$release_dirs" | wc -l)"'
queue_if "(( num_dirs > 10 ))", ->
  queue_raw_cmd 'echo "$release_dirs" | head -n1 | xargs rm -rfv'

### Close connection ###
script.end()
