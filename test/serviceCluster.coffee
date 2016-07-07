
_ = require 'lodash'
expect = require('chai').expect

{ cleanup
  clientConnect
  closeInstance
  parallel
  startService
} = require './testutils.coffee'

{ cleanupTimeout
  port
  user1
  user2
  user3
  roomName1
  roomName2
  redisConfig
} = require './config.coffee'

module.exports = ->

  instance1 = null
  instance2 = null
  socket1 = null
  socket2 = null
  socket3 = null
  socket4 = null
  socket5 = null

  afterEach (cb) ->
    @timeout cleanupTimeout
    cleanup [instance1, instance2], [socket1, socket2, socket3], cb
    chatService = socket1 = socket2 = socket3 = null

  it 'should send cluster bus custom messages', (done) ->
    event = 'someEvent'
    data = { key : 'value' }
    instance1 = startService _.assign {port : port}, redisConfig
    instance2 = startService _.assign {port : port+1}, redisConfig
    parallel [
      (cb) ->
        instance1.on 'ready', cb
      (cb) ->
        instance2.on 'ready', cb
    ], (error) ->
      expect(error).not.ok
      parallel [
        (cb) ->
          instance2.clusterBus.on event, (uid, d) ->
            expect(uid).equal(instance1.instanceUID)
            expect(d).deep.equal(data)
            cb()
        (cb) ->
          instance1.clusterBus.on event, (uid, d) ->
            expect(uid).equal(instance1.instanceUID)
            expect(d).deep.equal(data)
            cb()
        (cb) ->
          instance1.clusterBus.emit event, instance1.instanceUID, data
          cb()
      ], done

  it 'should actually remove other instances sockets from channel', (done) ->
    @timeout 4000
    @slow 2000
    instance1 = startService _.assign {port : port}, redisConfig
    instance2 = startService _.assign {port : port+1}, redisConfig
    instance1.addRoom roomName1, { owner : user2 }, ->
      parallel [
        (cb) ->
          socket1 = clientConnect user1, port
          socket1.on 'roomMessage', ->
            done new Error 'Not removed from channel'
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket2 = clientConnect user1, port+1
          socket2.on 'roomMessage', ->
            done new Error 'Not removed from channel'
          socket2.on 'loginConfirmed', ->
            socket2.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket3 = clientConnect user2, port
          socket3.on 'loginConfirmed', ->
            socket3.emit 'roomJoin', roomName1, cb
      ], (error) ->
        expect(error).not.ok
        socket3.emit 'roomAddToList', roomName1, 'blacklist', [user1], ->
          socket3.emit 'roomMessage', roomName1, {textMessage : 'hello'}
          setTimeout done, 1000

  it 'should disconnect users sockets across all instances', (done) ->
    instance1 = startService _.assign {port : port}, redisConfig
    instance2 = startService _.assign {port : port+1}, redisConfig
    parallel [
      (cb) ->
        socket1 = clientConnect user1, port
        socket1.on 'loginConfirmed', ->
          cb()
      (cb) ->
        socket2 = clientConnect user1, port+1
        socket2.on 'loginConfirmed', ->
          cb()
    ], (error) ->
      expect(error).not.ok
      parallel [
        (cb) ->
          socket1.on 'disconnect', -> cb()
        (cb) ->
          socket2.on 'disconnect', -> cb()
        (cb) ->
          instance1.disconnectUserSockets user1
          cb()
      ], done

  it 'should correctly update update presence info on shutdown', (done) ->
    instance1 = startService _.assign {port : port}, redisConfig
    instance2 = startService _.assign {port : port+1}, redisConfig
    ids = {}
    instance1.addRoom roomName1, null, ->
      parallel [
        (cb) ->
          socket1 = clientConnect user1, port
          socket1.on 'loginConfirmed', ->
            socket1.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket2 = clientConnect user2, port
          socket2.on 'loginConfirmed', ->
            socket2.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket3 = clientConnect user2, port+1
          socket3.on 'loginConfirmed', (u, d) ->
            ids[d.id] = d.id
            socket3.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket4 = clientConnect user2, port+1
          socket4.on 'loginConfirmed', (u, d) ->
            ids[d.id] = d.id
            socket4.emit 'roomJoin', roomName1, cb
        (cb) ->
          socket5 = clientConnect user3, port+1
          socket5.on 'loginConfirmed', ->
            socket5.emit 'roomJoin', roomName1, cb
      ], (error) ->
        expect(error).not.ok
        parallel [
          (cb) ->
            socket2.on 'roomLeftEcho', (roomName, id, njoined) ->
              expect(roomName).equal(roomName1)
              delete ids[id]
              if _.isEmpty ids
                expect(njoined).equal(1)
                cb()
          (cb) ->
            socket1.on 'roomUserLeft', (roomName, userName) ->
              expect(roomName).equal(roomName1)
              expect(userName).equal(user3)
              cb()
          (cb) ->
            socket2.on 'roomUserLeft', (roomName, userName) ->
              expect(roomName).equal(roomName1)
              expect(userName).equal(user3)
              cb()
          (cb) ->
            closeInstance(instance2).asCallback(cb)
        ], (error) ->
          expect(error).not.ok
          parallel [
            (cb) ->
              instance1.execUserCommand user2, 'listOwnSockets'
              , (error, sockets) ->
                expect(error).not.ok
                expect(_.size(sockets)).equal(1)
                cb()
            (cb) ->
              instance1.execUserCommand user3, 'listOwnSockets'
              , (error, sockets) ->
                expect(error).not.ok
                expect(_.size(sockets)).equal(0)
                cb()
            (cb) ->
              socket1.emit 'roomGetAccessList', roomName1, 'userlist',
              (error, list) ->
                expect(error).not.ok
                expect(list).lengthOf(2)
                expect(list).include(user1)
                expect(list).include(user2)
                cb()
          ], done

  it 'should cleanup incorrectly shutdown instance data', (done) ->
    instance1 = startService redisConfig
    instance2 = startService _.assign {port : port+1}, redisConfig
    uid = instance1.instanceUID
    instance1.addRoom roomName1, null, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          socket2 = clientConnect user2
          socket2.on 'loginConfirmed', ->
            instance1.redis.disconnect()
            instance1.io.httpServer.close()
            clearInterval instance1.hbtimer
            instance1 = null
            instance2.instanceRecovery uid, (error) ->
              expect(error).not.ok
              parallel [
                (cb) ->
                  instance2.execUserCommand user1, 'listOwnSockets'
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data).empty
                    cb()
                (cb) ->
                  instance2.execUserCommand user2, 'listOwnSockets'
                  , (error, data) ->
                    expect(error).not.ok
                    expect(data).empty
                    cb()
                (cb) ->
                  instance2.execUserCommand true, 'roomGetAccessList'
                  , roomName1, 'userlist', (error, data) ->
                    expect(error).not.ok
                    cb()
              ], done
