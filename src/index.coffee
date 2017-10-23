stream = require 'stream'
util = require 'util'
Rollbar = require 'rollbar'
_ = require 'underscore'

class RollbarStream extends stream.Writable
  constructor: (opts={}) ->
    streamWritableOpts = _({}).extend(opts, objectMode: true)
    streamWritableOpts.highwaterMark ?= 100
    super(streamWritableOpts)

    @client = opts.client ? do ->
      config = _(opts)
        .chain()
        .omit('token')
        .defaults({
          accessToken: opts.token
          branch: 'master'
          root: process.cwd()
          host: process.env.DYNO
        })
        .value()
      new Rollbar(config)

  _write: (obj, encoding, cb) ->
    customData = _(obj).omit('msg', 'err', 'req')
    customData.title = obj.msg if obj.msg?

    if obj.err?
      rebuiltErr = RollbarStream.rebuildErrorForReporting(obj.err)
      err = new Error(rebuiltErr.message)
      err.stack = rebuiltErr.stack
      customData.error = _.omit(obj.err, 'message', 'stack')
    else
      err = obj.msg

    if obj.req?
      req = _.clone obj.req
      req.socket ?= {} # fake a real request
      req.connection ?= {} # fake a real request
    else
      req = null

    @client.error err, req, customData, (e2) ->
      process.stderr.write util.format.call(util, 'Error logging to Rollbar', e2.stack or e2) + "\n" if e2?
      cb(e2) if cb?

  @FIBER_ROOT_CAUSE_SEPARATOR: /^\s{4}- - - - -\n/gm
  @rebuildErrorForReporting: (inErr) ->
    err = Object.create inErr

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

