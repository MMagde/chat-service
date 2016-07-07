
_ = require 'lodash'
expect = require('chai').expect

{ cleanup
  clientConnect
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
} = require './config.coffee'

module.exports = ->

  chatService = null
  socket1 = null
  socket2 = null
  socket3 = null

  afterEach (cb) ->
    @timeout cleanupTimeout
    cleanup chatService, [socket1, socket2, socket3], cb
    chatService = socket1 = socket2 = socket3 = null

  it 'should support a server side user disconnection', (done) ->
    chatService = startService()
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', (u) ->
      expect(u).equal(user1)
      socket2 = clientConnect user1
      socket2.on 'loginConfirmed', (u) ->
        expect(u).equal(user1)
        parallel [
          (cb) ->
            chatService.disconnectUserSockets user1
            cb()
          (cb) ->
            socket1.on 'disconnect', ->
              expect(socket1.connected).not.ok
              cb()
          (cb) ->
            socket2.on 'disconnect', ->
              expect(socket2.connected).not.ok
              cb()
        ], done

  it 'should support adding users', (done) ->
    chatService = startService()
    chatService.addUser user1, { whitelistOnly : true }, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'directGetWhitelistMode', (error, data) ->
          expect(error).not.ok
          expect(data).true
          done()

  it 'should support deleting users', (done) ->
    chatService = startService()
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      chatService.disconnectUserSockets user1
      socket1.on 'disconnect', ->
        chatService.hasUser user1, (error, data) ->
          expect(error).not.ok
          expect(data).true
          chatService.deleteUser user1, (error) ->
            expect(error).not.ok
            chatService.hasUser user1, (error, data) ->
              expect(error).not.ok
              expect(data).false
              done()

  it 'should not delete connected users', (done) ->
    chatService = startService()
    socket1 = clientConnect user1
    socket1.on 'loginConfirmed', ->
      chatService.deleteUser user1, (error) ->
        expect(error).ok
        done()

  it 'should support deleting rooms', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, { owner : user1 }, ->
      chatService.hasRoom roomName1, (error, data) ->
        expect(error).not.ok
        expect(data).true
        chatService.deleteRoom roomName1, (error, data) ->
          expect(error).not.ok
          expect(data).not.ok
          chatService.hasRoom roomName1, (error, data) ->
            expect(error).not.ok
            expect(data).false
            done()

  it 'should check user names before adding', (done) ->
    chatService = startService()
    chatService.addUser 'user:1', null, (error, data) ->
      expect(error).ok
      expect(data).not.ok
      done()

  it 'should check existing users before adding new ones', (done) ->
    chatService = startService()
    chatService.addUser user1, null, ->
      chatService.addUser user1, null, (error, data) ->
        expect(error).ok
        expect(data).not.ok
        done()

  it 'should check commands names.', (done) ->
    chatService = startService()
    chatService.addUser user1, null, ->
      chatService.execUserCommand user1, 'nocmd', (error) ->
        expect(error).ok
        done()

  it 'should check for socket ids if required.', (done) ->
    chatService = startService()
    chatService.addUser user1, null, ->
      chatService.execUserCommand user1, 'roomJoin', (error) ->
        expect(error).ok
        done()

  it 'should support changing a room owner', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, { owner : user1 }, ->
      socket1 = clientConnect user1
      socket1.on 'loginConfirmed', ->
        socket1.emit 'roomJoin', roomName1, ->
          chatService.changeRoomOwner roomName1, user2, (error, data) ->
            expect(error).not.ok
            expect(data).not.ok
            socket1.emit 'roomGetOwner', roomName1, (error, data) ->
              expect(error).not.ok
              expect(data).equal(user2)
              done()

  it 'should support changing a room history limit', (done) ->
    sz = 100
    chatService = startService()
    chatService.addRoom roomName1, null, ->
      chatService.changeRoomHistoryMaxSize roomName1, sz, (error, data) ->
        expect(error).not.ok
        expect(data).not.ok
        socket1 = clientConnect user1
        socket1.on 'loginConfirmed', ->
          socket1.emit 'roomJoin', roomName1, ->
            socket1.emit 'roomHistoryInfo', roomName1, (error, data) ->
              expect(error).not.ok
              expect(data).ownProperty('historyMaxSize')
              expect(data.historyMaxSize).equal(sz)
              done()

  it 'should support room list checking', (done) ->
    chatService = startService()
    chatService.addRoom roomName1, { adminlist : [user1] }, ->
      chatService.roomHasInList roomName1, 'adminlist', user1
      , (error, data) ->
        expect(error).not.ok
        expect(data).true
        chatService.roomHasInList roomName1, 'adminlist', user2
        , (error, data) ->
          expect(error).not.ok
          expect(data).false
          done()

  it 'should support user list checking', (done) ->
    chatService = startService()
    chatService.addUser user1, { blacklist : [user2] }, ->
      chatService.userHasInList user1, 'blacklist', user2
      , (error, data) ->
        expect(error).not.ok
        expect(data).true
        chatService.userHasInList user1, 'blacklist', user3
        , (error, data) ->
          expect(error).not.ok
          expect(data).false
          done()
