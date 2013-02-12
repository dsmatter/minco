fs           = require "fs"
clc          = require "cli-color"
parse_config = (require "./config").parse
{deploy}     = require "./deploy"

# Logging facilities
log_err  = (t) -> console.log (clc.red t)
log_info = (t) -> console.log (clc.yellow t)

exports.run = (args) ->
  switch args[0]
    when "help" then print_usage()
    when "init" then init_config()
    when "deploy" then do_deploy args[1]
    else print_usage()

print_usage = ->
  commands =
    deploy: "Deploy using the given config file or $MINCO_CONFIG or deploy.json"
    init  : "Write an example config file"
    help  : "That's me"

  console.log "Usage: minco [command] [config file]\n"
  console.log (clc.yellow "Commands:")
  for cmd, desc of commands
    console.log "#{cmd}:\t#{desc}"

do_deploy = (config_path) ->
  # Which config file do we use?
  config_path ?= process.env["MINCO_CONFIG"] ? "deploy.json"
  if not fs.existsSync config_path
    log_err "Config file '#{config_path}' not found"
    process.exit 1

  # Parse config
  log_info "Using config file '#{config_path}'"
  try
    config = parse_config config_path
  catch e
    log_err "Error parsing config file: #{e}"
    process.exit 1

  # Deploy!
  deploy config

init_config = ->
  example_conf =
    server: "user@host"
    server_dir: "/path/to/dir/on/server"
    repo: "git@github.com:user/repo.git"
    branch: "master"
    shared_paths: ["node_modules", "db"]
    prerun: [
      "npm install",
      "cake build"
    ]
    run_cmd: "cake start"

  # Ensure deploy script doesn't exist
  config_path = "deploy.json"
  if fs.existsSync config_path
    log_err "File #{config_path} already exists. I better dont't touch it!"
    process.exit 1

  # Write config
  f = fs.createWriteStream config_path
  f.end (JSON.stringify example_conf)

