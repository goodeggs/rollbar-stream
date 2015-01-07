stream = require 'stream'
util = require 'util'
rollbar = require 'rollbar'
_ = require 'underscore'

class RollbarStream extends stream.Stream
  constructor: (opts={}) ->
    @writable = true

    opts.branch ?= 'master'
    opts.root ?= process.cwd()

    @client = opts.client ? do ->
      rollbar.init opts.token, _(opts).omit('token')
      rollbar

  write: (obj) ->
    data = {custom: _(obj).omit('msg', 'err', 'req')} # err, req handled explicitly below

    data.title = obj.msg if obj.msg?

    if obj.err?
      rebuiltErr = RollbarStream.rebuildErrorForReporting(obj.err)
      err = new Error(rebuiltErr.message)
      err.stack = rebuiltErr.stack
    else
      err = new Error(obj.msg)

    if obj.req?
      req = _.clone obj.req
      req.socket ?= {} # fake a real request
      req.connection ?= {} # fake a real request
    else
      req = null

    future = @client.future.handleErrorWithPayloadData(err, data, req)
    future.resolve (e2) ->
      util.print util.format.call(util, 'Error logging to Rollbar', e2.stack or e2) + "\n" if e2?
    future

  end: ->
    @emit 'end'

  setEncoding: (encoding) ->
    # noop

  @FIBER_ROOT_CAUSE_SEPARATOR: /^\s{4}- - - - -\n/gm
  @rebuildErrorForReporting: (inErr) ->
    err = _.clone inErr

    # Rewrite node_fibers stack traces so they're parseable by common
    # stack parsing libraries.  Node fibers attaches the root cause
    # at the end of the stack. Also, we want a separator line to show.
    if @FIBER_ROOT_CAUSE_SEPARATOR.test(err.stack)
      firstLine = err.stack.split('\n', 1)[0] + '\n'
      remainder = err.stack.replace(firstLine, '')
      remainder += '\n' unless /\n$/.test remainder
      stackLines = remainder.split(@FIBER_ROOT_CAUSE_SEPARATOR)
      stackLines.reverse()
      err.stack = (firstLine + stackLines.join('    at which_caused_the_waiting_fiber_to_throw:0:0\n')).trim()

    err

module.exports = RollbarStream

