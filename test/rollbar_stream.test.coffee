RollbarStream = require '../src'
rollbar = require 'rollbar'
sinon = require 'sinon'
chai = require 'chai'
expect = chai.expect
stackTrace = require 'stack-trace'
fibrous = require 'fibrous'
_ = require 'underscore'

describe 'RollbarStream', ->
  {client, stream} = {}

  beforeEach ->
    rollbar.init 'foo' # token
    sinon.stub(rollbar.api, 'postItem').yields()

    stream = new RollbarStream({client})

  afterEach ->
    rollbar.api.postItem.restore()

  describe '::write', ->

    describe 'an error with logged-in request data', ->
      {item, user} = {}

      beforeEach fibrous ->
        user =
          email: 'foo@bar.com'
          id: '1a2c3ffc4'

        stream.sync.write {
          msg: 'ack it broke!'
          err:
            message: 'some error message'
            data:
              field: 'extra data from boom'
          req:
            url: '/fake'
            headers: {host: 'localhost:3000'}
            ip: '127.0.0.1'
            user: _(user).pick('email', 'id')
          level: 20
          hello: 'world'
        }

        item = rollbar.api.postItem.lastCall.args[0]

      it 'sets the error', ->
        expect(item.body.trace.exception.message).to.equal 'some error message'
        expect(item.body.trace.exception.class).to.equal 'Error'

      it 'sets the person', ->
        expect(item.person.email).to.equal user.email
        expect(item.person.id).to.equal user.id

      it 'sets the request', ->
        expect(item.request.url).to.equal 'http://localhost:3000/fake'

      it 'sets the title', ->
        expect(item.title).to.equal 'ack it broke!'

      it 'dumps everything else in custom', ->
        expect(item.level).not.eql 20 # 'error', set by rollbar client
        expect(item.hello).to.be.undefined
        expect(item.field).to.be.undefined
        expect(item.custom).to.eql level: 20, hello: 'world', field: 'extra data from boom'


  describe 'RollbarStream.rebuildErrorForReporting', ->

    it 'rewrites fibrous stacks so stack parsers can grok it ', fibrous ->
      f = fibrous ->
        throw new Error('BOOM')
      future = f.future()
      try
        fibrous.wait(future)
        fail 'expect a failure'
      catch e
        # node fibers puts in dividers for root exceptions
        expect(e.stack).to.match /^\s{4}- - - - -$/gm
        lines = e.stack.split("\n").length - 3 # removing last line plus the separator left in by fibrous

        e = RollbarStream.rebuildErrorForReporting(e)

        parsed = stackTrace.parse(e)

        expect(parsed.length).to.eql lines
        expect(parsed[0].fileName).to.contain _(__filename.split('/')).last()
        expect(parsed[5].fileName).to.eql 'which_caused_the_waiting_fiber_to_throw'
        expect(parsed[5].lineNumber).to.eql null
        expect(parsed[5].columnNumber).to.eql null


