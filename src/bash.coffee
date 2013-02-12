clc = require "cli-color"

### Facilities to iteratively construct a bash script ###

class BashScript
  constructor: (stream) ->
    @stream = stream

  queue: (queue_f) ->
    try
      queue_f.call this
      @stream.end()

  raw: (raw) ->
    @stream.write raw + "\n"

  shebang: ->
    @raw "#!/bin/bash"

  echo: (text) ->
    @raw "echo " + (enclose_quotes text)

  log: (desc, cf=clc.white.bold) ->
    @echo (cf "----> " + desc)

  log_cmd: (cmd...) ->
    @log (cmd.join " "), clc.white

  if: (cond, then_queuer, else_queuer) ->
    @raw "if #{cond}; then"
    then_queuer.call this
    if else_queuer?
      @raw "else"
      else_queuer.call this
    @raw "fi"

  fun: (name, body_queuer) ->
    @raw "function " + name + " {"
    body_queuer.call this
    @raw "}"

  cmd: (cmd, args...) ->
    @log_cmd cmd, args...
    quoted_args = (args.map enclose_quotes).join " "
    @raw cmd + " " + quoted_args
    @error_check()

  cd: (dir) ->
    @cmd "cd", dir

  raw_cmd: (cmd) ->
    @log_cmd cmd
    @raw cmd
    @error_check()

  error_check: ->
    @if "[[ $? -ne 0 ]]",
      (->
        @log "Command failed with code $?", clc.red
        @raw "cleanup; exit 1"),
      (->
        @log "ok", clc.green)

enclose_quotes = (text) ->
  '"' + (text.replace /"/g, '"') + '"'

exports.BashScript = BashScript
