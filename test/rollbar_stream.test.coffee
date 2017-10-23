RollbarStream = require '../src'
Rollbar = require 'rollbar'
sinon = require 'sinon'
chai = require 'chai'
expect = chai.expect
stackTrace = require 'stack-trace'
fibrous = require 'fibrous'
_ = require 'underscore'

describe 'RollbarStream', ->
  {stream} = {}

  beforeEach ->
    stream = new RollbarStream({})

  describe 'end', ->
    finishEmitted = null

    beforeEach ->
      finishEmitted = false
      stream.on 'finish', -> finishEmitted = true

      sinon.stub(Rollbar::, 'error')

    afterEach ->
      Rollbar::error.restore()

    describe 'after a write', ->
      writeDone = null

      beforeEach ->
        writeDone = false
        stream.write {
          msg: 'ack it broke!'
          err:
            message: 'some error message'
            foobar: 'baz'
        }, ->
          writeDone = true

      describe 'with pending response', ->
        endComplete = null

        beforeEach ->
          expect(writeDone).to.be.false()

          endComplete = false
          stream.end ->
            endComplete = true

        it 'does not call the end callback', ->
          expect(endComplete).to.be.false()

        it 'does not emit the finish event', ->
          expect(finishEmitted).to.be.false()

        describe 'with completed response', ->
          beforeEach ->
            Rollbar::error.yield()

          it 'calls the end callback', ->
            expect(endComplete).to.be.true()

          it 'emits the finish event', ->
            expect(finishEmitted).to.be.true()

  describe '::write', ->

    beforeEach ->
      sinon.stub(Rollbar::, 'error').yields()

    afterEach ->
      Rollbar::error.restore()

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
            foobar: 'baz'
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

      it 'passes the title', ->
        expect(Rollbar::error.lastCall.args[2].title).to.equal 'ack it broke!'

      it 'passes the error', ->
        expect(Rollbar::error.lastCall.args[0]).to.be.an.instanceOf Error
        expect(Rollbar::error.lastCall.args[0].message).to.eql 'some error message'

      it 'passes the request', ->
        expect(Rollbar::error.lastCall.args[1].url).to.eql '/fake'

      it 'dumps everything else in custom (including stuff that was on the error object)', ->
        expect(Rollbar::error.lastCall.args[2]).to.eql {title: 'ack it broke!', level: 20, hello: 'world', error: { data: { field: 'extra data from boom' }, foobar: 'baz' }}

    describe 'an error with a custom fingerprint', ->

      it 'passes through the fingerprint to rollbar', fibrous ->
        stream.sync.write {
          msg: 'something I want to fingerpint',
          fingerprint: '123'
        }
        expect(Rollbar::error.lastCall.args[0]).to.eql 'something I want to fingerpint'
        expect(Rollbar::error.lastCall.args[2].fingerprint).to.eql '123'

  describe 'RollbarStream.rebuildErrorForReporting', ->
    {e} = {}

    beforeEach fibrous ->
      f = fibrous ->
        throw new Error('BOOM')
      future = f.future()
      try
        fibrous.wait(future)
        fail 'expect a failure'
      catch _e
        e = _e

    if process.version < 'v7' # fibrous stack traces changed in Node 7
      it '[Node < v7] rewrites fibrous stacks so stack parsers can grok it ', ->
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
    else
      it '[Node >= v7] passes through stack traces', ->
        expect(e.stack).not.to.match /^\s{4}- - - - -$/gm

        e2 = RollbarStream.rebuildErrorForReporting(e)
        expect(e2).to.eql e

